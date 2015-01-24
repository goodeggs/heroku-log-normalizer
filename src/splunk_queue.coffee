async = require 'async'
request = require 'request'
url = require 'url'
{EventEmitter} = require 'events'

class SplunkQueue extends EventEmitter

  @MAX_LOG_LINE_BATCH_SIZE: 1000

  constructor: (splunkURI, @stats) ->
    @_splunkUri = url.parse(splunkURI, true)
    [@_user, @_pass] = @_splunkUri.auth.split ':'

    @_queue = async.cargo @_send.bind(@), @constructor.MAX_LOG_LINE_BATCH_SIZE

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

  _send: (messages, cb) ->
    requestConfig = @_makeRequestConfig()
    requestConfig.qs = {sourcetype: 'json_predefined_timestamp'}
    requestConfig.body = messages.map(JSON.stringify).join("\r\n")
    request requestConfig, (err, res) =>
      if err? or res.statusCode >= 400
        console.error err or "Error: #{res.statusCode} response"
        console.error res.body if res?.body?.length
        @stats.increment 'error', messages.length
        @_queue.push messages # retry later
      else
        @stats.increment 'outgoing', messages.length
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

