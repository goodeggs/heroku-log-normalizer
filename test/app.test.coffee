{sinon, chai, expect} = require './test_helper'

librato = require 'librato-node'

app = require '../lib/app'
logdrainGateway = require '../lib/logdrain_gateway'

describe 'app', ->

  beforeEach ->
    sinon.stub(librato, 'increment')
    sinon.stub(logdrainGateway, 'write')

  afterEach ->
    librato.increment.restore()
    logdrainGateway.write.restore()

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
      expect(logdrainGateway.write).to.have.been.calledTwice
      expect(logdrainGateway.write.getCall(0).args[0].toString('utf8')).to.match ///^!Dec///
      expect(logdrainGateway.write.getCall(1).args[0].toString('utf8')).to.match ///^!Dec///

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
      expect(logdrainGateway.write).to.have.been.calledTwice

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
      expect(logdrainGateway.write).to.have.been.calledTwice
      expect(logdrainGateway.write.getCall(0).args[0].toString('utf8')).to.match ///^name=status&appInstance=production!Dec///
      expect(logdrainGateway.write.getCall(1).args[0].toString('utf8')).to.match ///^name=status&appInstance=production!Dec///

    it 'returns 200', ->
      expect(res.statusCode).to.equal 200


LOG_DATA = '''
  Dec 18 00:50:48 23.20.136.26 483 <13>1 2013-12-18T00:50:49.193368+00:00 d.1077786c-2728-483f-911f-89a0ef249867 app web.1 - - {"name":"www","appInstance":"production"}
  Dec 18 00:50:48 23.20.136.26 485 <13>1 2013-12-18T00:50:49.194368+00:00 d.1077786c-2728-483f-911f-89a0ef249867 heroku router - - sample#memory_total=190.64MB

'''
