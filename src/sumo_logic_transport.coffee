Transport = require './transport'
zlib = require 'zlib'

class SumoLogicTransport extends Transport

  constructor: (@_url, stats) ->
    super 'sumo_logic', stats

  _makeRequestConfig: ->
    {
      url: @_url
      method: 'POST'
      headers:
        'Content-Type': 'text/plain'
        'Content-Encoding': 'gzip'
      strictSSL: false
    }

  send: (messages, cb) ->
    body = messages.map (message) ->
      orderedMessage = {timestamp: message.timestamp}
      orderedMessage[k] = v for k, v of message when k isnt 'timestamp'
      JSON.stringify(orderedMessage)
    .join("\r\n")
    zlib.gzip body, (err, gzBody) =>
      return cb(err) if err?
      requestConfig = @_makeRequestConfig()
      requestConfig.timeout = 60 * 1000 # 60s
      requestConfig.body = gzBody
      @_request requestConfig, cb

module.exports = SumoLogicTransport

