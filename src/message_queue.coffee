async = require 'async'
request = require 'request'
{EventEmitter} = require 'events'

SplunkTransport = require './splunk_transport'
logger = (require './logger').child module: 'message_queue'

milliseconds = ([seconds, nanoSeconds]) ->
  seconds * 1000 + ~~(nanoSeconds / 1e6) # bitwise NOT NOT will floor

class MessageQueue extends EventEmitter

  @MAX_LOG_LINE_BATCH_SIZE: 1000

  constructor: (@_transport, @stats, @throttle = true) ->
    @_queue = async.cargo @_worker.bind(@), @constructor.MAX_LOG_LINE_BATCH_SIZE

  push: (args...) ->
    @_queue.push args...

  length: ->
    @_queue.length()

  flush: (cb) ->
    throw new Error("already flushing") if @_queue.drain?
    if @_queue.length()
      @_queue.drain = cb
    else
      cb()

  _worker: (messages, cb) ->
    timer = process.hrtime()
    @_send messages, =>
      return cb() unless @throttle

      # If the queue is low, wait before next job
      if @_queue.length() < MessageQueue.MAX_LOG_LINE_BATCH_SIZE
        return setTimeout cb, 5000

      wait = 0
      [seconds, nanoseconds] = process.hrtime(timer)
      if seconds < 1
        elapsed = milliseconds [seconds, nanoseconds]
        # Approximately call cb once per second
        # wait + time elapsed = 1 second
        wait = 1000 - elapsed
      setTimeout cb, wait


  _send: (messages, cb) ->
    @_transport.send messages, (err, {responseTime, size}) =>
      if err?
        @stats.increment 'error', messages.length
        @_queue.push messages # retry later
      else
        @stats.increment 'outgoing', messages.length
      logger.info {responseTime, size, queue: @_queue.length(), messages: messages.length}, 'Response complete'
      cb()


module.exports = MessageQueue

