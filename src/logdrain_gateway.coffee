SyslogParser = require('glossy').Parse
LRU = require 'lru-cache'
librato = require 'librato-node'
{LineStream} = require 'byline'
through = require 'through'
combine = require 'stream-combiner'

LEADING_JSON_OPTS = /^({[^!]+})!/
LEADING_SYSLOG_TRIMMER = /^[^<]+/

# keeps a cache of the last 100 unparseable messages so we can attempt to reassemble
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

syslogMessageToJSON = (syslogMessage) ->

  opts = {}

  # pull explicit options off the front of the line
  if (json = syslogMessage.match(LEADING_JSON_OPTS)?[1])?
    try opts = JSON.parse(json)
    syslogMessage = syslogMessage.replace(LEADING_JSON_OPTS, '')

  # trim some invalid syslog stuff Heroku adds
  syslogMessage = syslogMessage.replace(LEADING_SYSLOG_TRIMMER, '')

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

  # override any explicit options
  result[k] = v for k, v of opts

  return result

parseStream = through (line) ->
  librato.increment 'incoming'
  if json = syslogMessageToJSON(line.toString())
    @queue json
  else
    librato.increment 'invalid'

module.exports = combine(new LineStream, parseStream)

