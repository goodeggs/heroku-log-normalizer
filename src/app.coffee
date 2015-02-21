http = require 'http'
url = require 'url'
SyslogParser = require('glossy').Parse
LRU = require 'lru-cache'

logger = require('./logger').child module: 'app'

# keep a cache of the last 100 unparseable messages so we can attempt to reassemble
# loglines that heroku's drain infrastructure splits into 1024 character chunks.
invalidMessageCache = LRU(100)

extractMessage = (syslogMessage, parser) ->
  try
    return parser(syslogMessage.message)
  catch e
    key = [syslogMessage.host, syslogMessage.pid, syslogMessage.time].join('|')
    if (current = invalidMessageCache.get(key))?
      current += syslogMessage.message
      try
        msg = parser(current)
        librato.increment 'reconstructed'
        return msg
      catch e
        invalidMessageCache.set key, current
    else
      invalidMessageCache.set key, syslogMessage.message
  return null

LEADING_TRIMMER = /^[^<]+/

syslogMessageToJSON = (syslogMessage) ->
  parsed = SyslogParser.parse syslogMessage.replace(LEADING_TRIMMER, '')

  result = switch parsed.appName
    when 'heroku'
      extractMessage parsed, ((msg) -> {msg})
    when 'app'
      extractMessage parsed, JSON.parse
    else
      # unknown format
      {msg: parsed.message, timestamp: new Date().toISOString()}

  return null unless result?

  # make time field match splunk's expectation of timestamp
  result.timestamp ?= result.time or parsed.time.toISOString()
  delete result.time

  # clean some fields from the syslog header
  delete parsed.originalMessage
  delete parsed.message

  result.syslog = parsed
  return result

app = (librato, messageQueue) ->

  http.createServer (req, res) ->

    # Herkou logdrain is picky, see https://devcenter.heroku.com/articles/log-drains
    res.setHeader 'Content-Length', 0
    res.setHeader 'Connection', 'close'

    try
      urlParts = url.parse(req.url)

      if urlParts.path.indexOf("/drain") is 0
        data = ''

        req.on 'data', (chunk) ->
          data += chunk

        req.on 'end', ->
          res.writeHead 200
          res.end()

          syslogMessages = if data.indexOf("\n") > -1 then data.split("\n") else [data, ""]
          syslogMessages.pop()

          if syslogMessages.length
            librato.increment 'incoming', syslogMessages.length
            for syslogMessage in syslogMessages
              if json = syslogMessageToJSON(syslogMessage)
                messageQueue.push json
              else
                librato.increment 'invalid'

      else
        res.writeHead 404
        res.end()
    catch e
      logger.error e.stack ? e
      res.writeHead 503
      res.end()

module.exports = app

