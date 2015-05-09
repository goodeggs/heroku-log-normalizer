http = require 'http'
url = require 'url'
LRU = require 'lru-cache'
librato = require 'librato-node'
through = require 'through'
combine = require 'stream-combiner'

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
      req.pipe combine(herokuSyslogStream(), withQuery(urlParts.query), syslogToJsonStream), end: false
      req.on 'end', ->
        res.writeHead 200
        res.end()
  catch e
    logger.error e.stack ? e
    res.writeHead 503
    res.end()

module.exports = app

