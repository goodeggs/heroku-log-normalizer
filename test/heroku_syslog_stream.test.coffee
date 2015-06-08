{expect, sinon} = require './test_helper'
fs = require 'fs'
path = require 'path'
herokuSyslogStream = require '../lib/heroku_syslog_stream'

describe 'herokuSyslogStream', ->

  describe 'a single message', ->
    {log} = {}

    beforeEach ->
      log = fs.createReadStream path.join(__dirname, 'fixtures/single.log')

    it 'extracts messages', (done) ->
      onData = sinon.spy()
      stream = herokuSyslogStream()
      stream.on 'data', onData
      log.pipe(stream)
      stream.on 'end', ->
        expect(onData.callCount).to.equal 1
        expect(onData.getCall(0).args[0]).to.equal '<45>1 2015-05-09T20:21:25.608433+00:00 host heroku web.1 - State changed from starting to crashed\n'
        done()

  describe 'a multiple messages including a wrapped line', ->
    {splitLog} = {}

    beforeEach ->
      splitLog = fs.createReadStream path.join(__dirname, 'fixtures/split.log')

    it 'extracts messages', (done) ->
      onData = sinon.spy()
      stream = herokuSyslogStream()
      stream.on 'data', onData
      splitLog.pipe(stream)
      stream.on 'end', ->
        expect(onData.callCount).to.equal 3
        expect(onData.getCall(0).args[0]).to.equal '<172>1 2015-05-09T20:21:24+00:00 host heroku logplex - Error L10 (output buffer overflow): 1 messages dropped since 2015-05-09T20:19:03+00:00.'
        done()

  describe 'chunked writes', ->

    it 'extracts messages', (done) ->
      onData = sinon.spy()
      stream = herokuSyslogStream()
      stream.on 'data', onData
      stream.on 'end', ->
        expect(onData.callCount).to.equal 6
        expect(onData.getCall(4).args[0]).to.equal '<172>1 2015-06-08T21:53:21+00:00 host heroku logplex - Error L10 (output buffer overflow): 4 messages dropped since 2015-06-08T21:46:44+00:00.'
        expect(onData.getCall(5).args[0]).to.equal '<190>1 2015-06-08T21:53:21.461086+00:00 host app web.1 - {"name":"status","env":"production","appInstance":"production","hostname":"8b44da60-a089-462b-97ed-e274dcf2e069","pid":3,"requestId":"f76651b2-8f29-4c21-8f5a-92bd9f0cfb3d","level":30,"req":{"headers":{"host":"status.goodeggs.com","connection":"close","user-agent":"Pingdom.com_bot_version_1.4_(http://www.pingdom.com/)","fastly-client-ip":"174.34.162.242","x-forwarded-for":"174.34.162.242, 23.235.39.31","x-forwarded-server":"cache-atl6231-ATL","x-forwarded-host":"status.goodeggs.com","accept-encoding":"gzip","fastly-ssl":"1","x-timer":"S1433800401.348717,VS0","x-ua-device":"bot","accept":"text/html, */*","x-varnish":"2870720044","fastly-ff":"cache-atl6231-ATL","x-request-id":"f76651b2-8f29-4c21-8f5a-92bd9f0cfb3d","x-forwarded-proto":"https","x-forwarded-port":"443","via":"1.1 vegur","connect-time":"2","x-request-start":"1433800401411","total-route-time":"0"},"method":"GET","query":{},"ip":"10.123.194.135","path":"/","host":"status.goodeggs.com","body":{},"url":"http://status.goodeggs.com/"},"res":{"status":200,"contentLength":"40442"},"responseTime":43,"msg":"GET / HTTP/1.1","time":"2015-06-08T21:53:21.460Z","v":0}\n'
        done()

      stream.write new Buffer('142 <172>1 2015-06-08T21:50:22+00:00 host heroku logplex - Error L10 (output buffer overflow): 3 messages dropped since 2015-06-08T21:47:22+00:00.253 <158>1 2015-06-08T21:50:22.082451+00:00 host heroku router - at=info method=GET path="/" host=status.goodeggs.com request_id=42afbd37-571a-4309-a329-4d576ad520c6 fwd="78.40.124.16,185.31.17.42" dyno=web.2 connect=5ms service=86ms status=200 bytes=40524\n')
      stream.write new Buffer('142 <172>1 2015-06-08T21:53:21+00:00 host heroku logplex - Error L10 (output buffer overflow): 6 messages dropped since 2015-06-08T21:47:43+00:00.255 <158>1 2015-06-08T21:53:21.466271+00:00 host heroku router - at=info method=GET path="/" host=status.goodeggs.com request_id=f76651b2-8f29-4c21-8f5a-92bd9f0cfb3d fwd="174.34.162.242,23.235.39.31" dyno=web.1 connect=2ms service=49ms status=200 bytes=40800\n')
      stream.write new Buffer('142 <172>1 2015-06-08T21:53:21+00:00 host heroku logplex - Error L10 (output buffer overflow): 4 messages dropped since 2015-06-08T21:46:44+00:00.1188 <190>1 2015-06-08T21:53:21.461086+00:00 host app web.1 - {"name":"status","env":"production","appInstance":"production","hostname":"8b44da60-a089-462b-97ed-e274dcf2e069","pid":3,"requestId":"f76651b2-8f29-4c21-8f5a-92bd9f0cfb3d","level":30,"req":{"headers":{"host":"status.goodeggs.com","connection":"close","user-agent":"Pingdom.com_bot_version_1.4_(http://www.pingdom.com/)","fastly-client-ip":"174.34.162.242","x-forwarded-for":"174.34.162.242, 23.235.39.31","x-forwarded-server":"cache-atl6231-ATL","x-forwarded-host":"status.goodeggs.com","accept-encoding":"gzip","fastly-ssl":"1","x-timer":"S1433800401.348717,VS0","x-ua-device":"bot","accept":"text/html, */*","x-varnish":"2870720044","fastly-ff":"cache-atl6231-ATL","x-request-id":"f76651b2-8f29-4c21-8f5a-92bd9f0cfb3d","x-forwarded-proto":"https","x-forwarded-port":"443","via":"1.1 vegur","connect-time":"2","x-request-start":"1433800401411","total')
      stream.write new Buffer('-route-time":"0"},"method":"GET","query":{},"ip":"10.123.194.135","path":"/","host":"status.goodeggs.com","body":{},"url":"http://status.goodeggs.com/"},"res":{"status":200,"contentLength":"40442"},"responseTime":43,"msg":"GET / HTTP/1.1","time":"2015-06-08T21:53:21.460Z","v":0}\n')
      stream.end()

