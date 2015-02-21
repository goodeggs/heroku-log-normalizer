http = require 'http'
url = require 'url'
LRU = require 'lru-cache'
librato = require 'librato-node'

logdrainGateway = require './logdrain_gateway'
logger = require('./logger').child module: 'app'

frameIdCache = LRU(2000)

app = http.createServer (req, res) ->

  # Herkou logdrain is picky, see https://devcenter.heroku.com/articles/log-drains
  res.setHeader 'Content-Length', 0
  res.setHeader 'Connection', 'close'

  try
    urlParts = url.parse(req.url)

    if urlParts.path.indexOf("/drain") is 0
      frameId = req.headers['logplex-frame-id']
      if frameIdCache.get(frameId)?
        librato.increment 'duplicate'
        res.writeHead 200
        res.end()
      else
        frameIdCache.set frameId, 1
        req.pipe logdrainGateway, end: false
        req.on 'end', ->
          res.writeHead 200
          res.end()
    else
      res.writeHead 404
      res.end()
  catch e
    logger.error e.stack ? e
    res.writeHead 503
    res.end()

module.exports = app

