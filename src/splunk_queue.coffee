async = require 'async'
request = require 'request'
url = require 'url'
{EventEmitter} = require 'events'

logger = (require './logger').child module: 'splunk_queue'

milliseconds = ([seconds, nanoSeconds]) ->
  seconds * 1000 + ~~(nanoSeconds / 1e6) # bitwise NOT NOT will floor


class SplunkQueue extends EventEmitter

  @MAX_LOG_LINE_BATCH_SIZE: 1000

  constructor: (splunkURI, @stats, @throttle = true) ->
    @_splunkUri = url.parse(splunkURI, true)
    [@_user, @_pass] = @_splunkUri.auth.split ':'

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
      if @_queue.length() < SplunkQueue.MAX_LOG_LINE_BATCH_SIZE
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
    requestConfig = @_makeRequestConfig()
    requestConfig.qs = {sourcetype: 'json_predefined_timestamp'}
    requestConfig.body = messages.map(JSON.stringify).join("\r\n")
    @stats.increment 'splunk.count'
    timer = process.hrtime()
    request requestConfig, @_onComplete(cb, timer, messages)

  _onComplete: (cb, timer, messages) ->
    (err, res) =>
        responseTime = milliseconds process.hrtime(timer)
        @stats.timing 'splunk.time', responseTime
        @stats.timing 'splunk.size', res?.req?.body?.length
        if err? or res.statusCode >= 400
          logger.error err if err?
          logger.error {msg: "Error: #{res.statusCode} response", status: res.statusCode, body: res.body} if res?
          @stats.increment 'error', messages.length
          @_queue.push messages # retry later
        else
          @stats.increment 'outgoing', messages.length
        logger.info 'Response complete', time: responseTime, queue: @_queue.length(), messages: messages.length, size: res?.req?.body?.length
        cb()


  _makeRequestConfig: ->
    {
      url: "#{@_splunkUri.protocol}//#{@_splunkUri.host}#{@_splunkUri.path}"
      method: 'POST'
      auth: {user: @_user, pass: @_pass}
      headers:
        'Content-Type': 'text/plain'
      strictSSL: false
    }

module.exports = SplunkQueue

