http = require 'http'
url = require 'url'
LRU = require 'lru-cache'
librato = require 'librato-node'
{LineStream} = require 'byline'
through = require 'through'
combine = require 'stream-combiner'

logdrainGateway = require './logdrain_gateway'
logger = require('./logger').child module: 'app'

withQuery = (query) ->
  through (buf) ->
    @queue Buffer.concat([new Buffer("#{query or ''}!", 'utf8'), buf])

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
      req.pipe combine(new LineStream, withQuery(urlParts.query), logdrainGateway), end: false
      req.on 'end', ->
        res.writeHead 200
        res.end()
  catch e
    logger.error e.stack ? e
    res.writeHead 503
    res.end()

module.exports = app

