request = require 'request'
url = require 'url'

logger = (require './logger').child module: 'splunk_transport'

milliseconds = ([seconds, nanoSeconds]) ->
  seconds * 1000 + ~~(nanoSeconds / 1e6) # bitwise NOT NOT will floor

class SplunkTransport
  constructor: (splunkURI, @stats) ->
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

    @stats.increment 'splunk.count'
    timer = process.hrtime()
    request requestConfig, @_onComplete(cb, {timer, messages, size: requestConfig.body.length})

  _onComplete: (cb, {timer, messages, size}) ->
    (err, res) =>
      responseTime = milliseconds process.hrtime(timer)
      @stats.timing 'splunk.time', responseTime
      @stats.timing 'splunk.size', size
      logger.error err if err?
      if !err and res.statusCode >= 400
        logger.error {status: res.statusCode, body: res.body}, "Error: #{res.statusCode} response"
        err = new Error("#{res.statusCode} response")
        err.code = res.statusCode
        err.body = res.body
      cb(err, {responseTime, size})

module.exports = SplunkTransport

