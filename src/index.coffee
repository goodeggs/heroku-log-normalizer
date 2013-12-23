SyslogParser = require('glossy').Parse
LogFmt = require 'logfmt'
LRU = require 'lru-cache'
librato = require 'librato-node'
redis = require 'redis'
fibrous = require 'fibrous'
argv = require('optimist')
  .usage('Read syslog lines from the given redis list, normalize them to JSON, and write them to stdout.\nUsage: $0')
  .demand('l')
  .alias('l', 'list')
  .describe('l', 'list key')
  .alias('p', 'port')
  .describe('p', 'redis port')
  .alias('h', 'host')
  .describe('h', 'redis host')
  .default(p: 6379, h: '127.0.0.1')
  .argv

running = true

librato.configure email: process.env.LIBRATO_EMAIL, token: process.env.LIBRATO_TOKEN
librato.start()

redisClient = redis.createClient(argv.port, argv.host)
redisClient.on 'error', (err) ->
  console.error(err)

track = (metric) ->
  librato.increment "production.heroku_log_normalizer.#{metric}"

# keep a cache of the last 100 unparseable messages so we can attempt to reassemble
# loglines that heroku's drain infrastructure splits into 1024 character chunks.
invalidMessageCache = LRU(100)

extractMessage = (syslogMessage, parser) ->
  try
    return parser(syslogMessage.message)
  catch e
    track 'invalid'
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

syslogMessageToJSON = (syslogMessage) ->
  parsed = SyslogParser.parse(syslogMessage)
  
  result = switch parsed.appName
    when 'heroku'
      extractMessage parsed, LogFmt.parse
    when 'app'
      extractMessage parsed, JSON.parse
    else
      # unknown format
      {msg: parsed.message, timestamp: new Date().toISOString()}
      
  return null unless result?
  
  # make time field match splunk's expectation of timestamp
  result.timestamp ?= result.time
  delete result.time

  # clean some fields from the syslog header
  delete parsed.originalMessage
  delete parsed.message
  
  result.syslog = parsed
  return result

fibrous.sleep = (timeoutMs) ->
  future = new fibrous.Future()
  setTimeout(future.return.bind(future), timeoutMs)
  future.wait()

fibrous.run ->
  while running
    while running and redisClient.connected
      try
        # called this way because redisClient has a method called sync
        syslogMessage = redisClient.rpop.sync.call(redisClient, argv.list)
        break if not syslogMessage?
        
        track 'incoming'
        
        json = syslogMessageToJSON(syslogMessage)
        break if not json?

        console.log JSON.stringify(json)
        track 'outgoing'
      
      catch e
        console.error e
      
    fibrous.sleep 500
  return null # prevents accumulation leak

process.on 'SIGINT', ->
  console.error 'Got SIGINT.  Exiting.'
  running = false
  librato.stop()
  redisClient.quit()
  process.exit(0)

