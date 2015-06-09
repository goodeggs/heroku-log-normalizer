http = require 'http'
url = require 'url'
LRU = require 'lru-cache'
librato = require 'librato-node'
through = require 'through'
combine = require 'stream-combiner'
onFinished = require 'on-finished'

herokuSyslogStream = require './heroku_syslog_stream'
syslogToJsonStream = require './syslog_to_json_stream'
logger = require('./logger').child module: 'app'

withQuery = (query) ->
  through (data) ->
    @queue "#{query or ''}!#{data}"

frameIdCache = LRU(2000)

app = http.createServer (req, res) ->

  # Herkou logdrain is picky, see https://devcenter.heroku.com/articles/log-drains
  res.setHeader 'Content-Length', 0
  res.setHeader 'Connection', 'close'

  try
    urlParts = url.parse(req.url)

    if urlParts.pathname isnt '/drain'
      res.writeHead 404
      res.end()
      return

    frameId = req.headers['logplex-frame-id']
    if frameIdCache.get(frameId)?
      librato.increment 'duplicate'
      res.writeHead 200
      res.end()
    else
      frameIdCache.set frameId, 1

      messageStream = combine herokuSyslogStream(), withQuery(urlParts.query)

      # listening for 'data' rather than combining above avoids an EventEmitter
      # memory leak because syslogToJsonStream lives across requests
      messageStream.on 'data', syslogToJsonStream.write.bind(syslogToJsonStream)

      req.pipe messageStream

      # onFinished handles error events, so a closed socket doesn't crash the process
      onFinished req, (err) ->
        logger.error(err.stack or err) if err?
        res.writeHead(err? and 503 or 200)
        res.end()
  catch e
    logger.error e.stack ? e
    res.writeHead 503
    res.end()

module.exports = app

