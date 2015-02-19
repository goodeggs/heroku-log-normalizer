Transport = require './transport'

class SumoLogicTransport extends Transport

  constructor: (@_url, stats) ->
    super 'sumo_logic', stats

  _makeRequestConfig: ->
    {
      url: @_url
      method: 'POST'
      headers:
        'Content-Type': 'text/plain'
      strictSSL: false
    }

  send: (messages, cb) ->
    requestConfig = @_makeRequestConfig()
    requestConfig.body = messages.map(JSON.stringify).join("\r\n")
    requestConfig.timeout = 60 * 1000 # 60s
    @_request requestConfig, cb

module.exports = SumoLogicTransport

