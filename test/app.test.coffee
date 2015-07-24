{sinon, chai, expect} = require './test_helper'

async = require 'async'
librato = require 'librato-node'

app = require '../src/app'
syslogToJsonStream = require '../src/syslog_to_json_stream'

describe 'app', ->

  beforeEach ->
    sinon.stub(librato, 'increment')
    sinon.stub(syslogToJsonStream, 'write')

  afterEach ->
    librato.increment.restore()
    syslogToJsonStream.write.restore()

  describe 'a POST with two log lines', ->
    {res} = {}

    beforeEach (done) ->
      chai.request(app)
        .post '/drain'
        .set 'Logplex-Frame-Id', '1'
        .send LOG_DATA
        .end (err, _res) ->
          res = _res
          done(err)

    it 'enqueues two messages', ->
      expect(syslogToJsonStream.write).to.have.been.calledTwice
      expect(syslogToJsonStream.write.getCall(0).args[0]).to.equal '!<172>1 2015-05-09T20:21:24+00:00 host heroku logplex - Error L10 (output buffer overflow): 1 messages dropped since 2015-05-09T20:19:03+00:00.'
      expect(syslogToJsonStream.write.getCall(1).args[0]).to.equal '!<45>1 2015-05-09T20:21:25.608433+00:00 host heroku web.1 - State changed from starting to crashed\n'

    it 'returns 200', ->
      expect(res.statusCode).to.equal 200

    it 'respects Heroku header wishes', ->
      expect(res.headers['content-length']).to.equal '0'
      expect(res.headers['connection']).to.equal 'close'

  describe 'two POSTs with the same Logplex-Frame-Id', ->
    {res1, res2} = {}

    beforeEach (done) ->
      chai.request(app)
        .post '/drain'
        .set 'Logplex-Frame-Id', 'abcdefg'
        .send LOG_DATA
        .end (err, _res1) ->
          res1 = _res1
          done(err) if err?
      chai.request(app)
        .post '/drain'
        .set 'Logplex-Frame-Id', 'abcdefg'
        .send LOG_DATA
        .end (err, _res2) ->
          res2 = _res2
          done(err)

    it 'logs one set of messages', ->
      expect(syslogToJsonStream.write).to.have.been.calledTwice

    it 'increments the duplicate counter', ->
      expect(librato.increment).to.have.been.calledWith 'duplicate'

    it 'always returns 200', ->
      expect(res1.statusCode).to.equal 200
      expect(res2.statusCode).to.equal 200

  describe 'a POST with two log lines and query params', ->
    {res} = {}

    beforeEach (done) ->
      chai.request(app)
        .post '/drain'
        .query name: 'status', appInstance: 'production'
        .set 'Logplex-Frame-Id', '2'
        .send LOG_DATA
        .end (err, _res) ->
          res = _res
          done(err)

    it 'enqueues two messages with options', ->
      expect(syslogToJsonStream.write).to.have.been.calledTwice
      expect(syslogToJsonStream.write.getCall(0).args[0]).to.equal 'name=status&appInstance=production!<172>1 2015-05-09T20:21:24+00:00 host heroku logplex - Error L10 (output buffer overflow): 1 messages dropped since 2015-05-09T20:19:03+00:00.'
      expect(syslogToJsonStream.write.getCall(1).args[0]).to.equal 'name=status&appInstance=production!<45>1 2015-05-09T20:21:25.608433+00:00 host heroku web.1 - State changed from starting to crashed\n'

    it 'returns 200', ->
      expect(res.statusCode).to.equal 200

  describe 'given EventEmitter.defaultMaxListeners + 1 POSTs', ->
    {agent} = {}

    beforeEach ->
      agent = chai.request.agent(app)

    # this test is here to get Node to spit out the EventEmitter maxListeners warning,
    # but even if it does this test will succeed.
    it 'all requests end in 200 OK', (done) ->
      async.eachSeries [1..11], (idx, cb) ->
        agent
          .post '/drain'
          .set 'Logplex-Frame-Id', idx
          .send LOG_DATA
          .end (err, res) ->
            expect(err).not.to.exist
            expect(res).to.have.status 200
            cb()
      , done


LOG_DATA = '''
  142 <172>1 2015-05-09T20:21:24+00:00 host heroku logplex - Error L10 (output buffer overflow): 1 messages dropped since 2015-05-09T20:19:03+00:00.98 <45>1 2015-05-09T20:21:25.608433+00:00 host heroku web.1 - State changed from starting to crashed

'''
