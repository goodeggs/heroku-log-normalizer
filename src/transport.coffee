request = require 'request'
logger = require './logger'

milliseconds = ([seconds, nanoSeconds]) ->
  seconds * 1000 + ~~(nanoSeconds / 1e6) # bitwise NOT NOT will floor

class Transport

  constructor: (@_name, @_stats) ->
    @_logger = logger.child module: "#{@_name}_transport"

  send: (messages, cb) ->
    throw new Error('implement me')

  _request: (opts, cb) ->
    @_stats.increment "#{@_name}.count"
    timer = process.hrtime()
    request opts, @_onComplete(cb, {timer, size: opts.body.length})

  _onComplete: (cb, {timer, size}) ->
    (err, res) =>
      responseTime = milliseconds process.hrtime(timer)
      @_stats.timing "#{@_name}.time", responseTime
      @_stats.timing "#{@_name}.size", size
      @_logger.error err if err?
      if !err and res.statusCode >= 400
        @_logger.error {status: res.statusCode, body: res.body}, "Error: #{res.statusCode} response"
        err = new Error("#{res.statusCode} response")
        err.code = res.statusCode
        err.body = res.body
      cb(err, {responseTime, size})

module.exports = Transport

