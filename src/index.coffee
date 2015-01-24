SyslogParser = require('glossy').Parse
LRU = require 'lru-cache'
librato = require 'librato-node'
http = require 'http'
url = require 'url'
os = require 'os'
SplunkQueue = require './splunk_queue'

librato.configure
  email: process.env.LIBRATO_EMAIL
  token: process.env.LIBRATO_TOKEN
  source: os.hostname() # Worker number?
  prefix: 'heroku_log_normalizer.'

librato.start()

splunkQueue = new SplunkQueue process.env.SPLUNK_URI, librato

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

app = http.createServer (req, res) ->
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
              splunkQueue.push json
            else
              librato.increment 'invalid'

    else
      res.writeHead 404
      res.end()
  catch e
    console.error e.stack ? e
    res.writeHead 503
    res.end()

app.listen process.env.PORT ? 8000

process.on 'SIGINT', ->
  console.error 'Got SIGINT.  Exiting.'
  app.close ->
    console.error 'Waiting for splunk queue to drain...'
    pollInterval = setInterval((-> console.error "#{splunkQueue.length()} messages left to send"), 1000)
    splunkQueue.flush ->
      console.error 'drained!'
      clearInterval pollInterval
      process.exit 0

