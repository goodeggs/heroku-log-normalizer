url = require 'url'

Transport = require './transport'

class SplunkTransport extends Transport

  constructor: (splunkURI, stats) ->
    super 'splunk', stats
    @_splunkUri = url.parse(splunkURI, true)
    [@_user, @_pass] = @_splunkUri.auth.split ':'

  _makeRequestConfig: ->
    {
      url: "#{@_splunkUri.protocol}//#{@_splunkUri.host}#{@_splunkUri.path}"
      method: 'POST'
      auth: {user: @_user, pass: @_pass}
      headers:
        'Content-Type': 'text/plain'
      strictSSL: false
    }

  send: (messages, cb) ->
    requestConfig = @_makeRequestConfig()
    requestConfig.qs = {sourcetype: 'json_predefined_timestamp'}
    requestConfig.body = messages.map(JSON.stringify).join("\r\n")
    requestConfig.timeout = 10 * 60 * 1000  # Long timeout (ms) of 10 min. We've seen Splunk  time out at 60 seconds,
                                            # but not need to set a similar timeout. We only care if heroku logplex is
                                            # getting backed up. 10 minutes is probably a good compromise.
    @_request requestConfig, cb

module.exports = SplunkTransport

