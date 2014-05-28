SyslogParser = require('glossy').Parse
LRU = require 'lru-cache'
librato = require 'librato-node'
async = require 'async'
http = require 'http'
url = require 'url'
request = require 'request'

librato.configure email: process.env.LIBRATO_EMAIL, token: process.env.LIBRATO_TOKEN
librato.start()

track = (metric, count=1) ->
  librato.increment "production.heroku_log_normalizer.#{metric}", count

splunkConfig = do ->
  splunkUri = url.parse(process.env.SPLUNK_URI, true)
  [user, pass] = splunkUri.auth.split ':'
  return ->
    {
      url: "#{splunkUri.protocol}//#{splunkUri.host}#{splunkUri.path}"
      method: 'POST'
      auth: {user, pass}
      headers:
        'Content-Type': 'text/plain'
      strictSSL: false
    }

MAX_LOG_LINE_BATCH_SIZE = 100
splunkQueue = async.cargo (messages, cb) ->
  requestConfig = splunkConfig()
  requestConfig.qs = {sourcetype: 'json_predefined_timestamp'}
  requestConfig.body = messages.join("\r\n")
  request requestConfig, (err, res) ->
    if err? or res.statusCode >= 500
      console.error err or "Error: #{res.statusCode} response"
      track 'error', messages.length
      splunkQueue.push messages # retry later
    else
      track 'outgoing', messages.length
    cb()
, MAX_LOG_LINE_BATCH_SIZE

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
        track 'reconstructed'
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
          track 'incoming', syslogMessages.length
          for syslogMessage in syslogMessages
            if json = syslogMessageToJSON(syslogMessage)
              splunkQueue.push JSON.stringify(json)
            else
              track 'invalid'

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
    if splunkQueue.length()
      console.error 'Waiting for splunk queue to drain...'
      pollInterval = setInterval((-> console.error "#{splunkQueue.length()} messages left to send"), 1000)
      splunkQueue.drain = ->
        clearInterval pollInterval
        console.error 'drained!'
        process.exit 0
    else
      process.exit 0

