SyslogParser = require('glossy').Parse
LRU = require 'lru-cache'
librato = require 'librato-node'
through = require 'through'
combine = require 'stream-combiner'
qs = require 'querystring'

# keeps a cache of the last 100 unparseable messages so we can attempt to reassemble
# loglines that heroku's drain infrastructure splits into 10000 byte chunks.
# https://devcenter.heroku.com/articles/logging#log-format
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

syslogMessageToJSON = (syslogMessage) ->

  # pull explicit options off the front of the line
  [opts, syslogMessage...] = syslogMessage.split('!')
  opts = qs.parse opts
  syslogMessage = syslogMessage.join('!') # reassemble the rest

  parsed = SyslogParser.parse syslogMessage

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

  # clean some fields from the syslog header, and add it at syslog
  delete parsed.originalMessage
  delete parsed.message
  result.syslog = parsed

  # apply (as defaults) any options we were provided
  result[k] ?= v for k, v of opts

  return result

parseStream = through (line) ->
  librato.increment 'incoming'
  if json = syslogMessageToJSON(line.toString())
    @queue json
  else
    librato.increment 'invalid'

module.exports = parseStream

