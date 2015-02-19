request = require 'request'
logger = require './logger'

milliseconds = ([seconds, nanoSeconds]) ->
  seconds * 1000 + ~~(nanoSeconds / 1e6) # bitwise NOT NOT will floor

class Transport

  constructor: ->
    @logger = logger.child module: "#{@name}_transport"

  request: (opts, cb) ->
    @stats.increment "#{@name}.count"
    timer = process.hrtime()
    request opts, @_onComplete(cb, {timer, size: opts.body.length})

  _onComplete: (cb, {timer, size}) ->
    (err, res) =>
      responseTime = milliseconds process.hrtime(timer)
      @stats.timing "#{@name}.time", responseTime
      @stats.timing "#{@name}.size", size
      @logger.error err if err?
      if !err and res.statusCode >= 400
        @logger.error {status: res.statusCode, body: res.body}, "Error: #{res.statusCode} response"
        err = new Error("#{res.statusCode} response")
        err.code = res.statusCode
        err.body = res.body
      cb(err, {responseTime, size})

module.exports = Transport

