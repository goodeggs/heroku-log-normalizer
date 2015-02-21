{sinon, chai, expect} = require './test_helper'

librato = require 'librato-node'

appBuilder = require '../lib/app'
MessageQueue = require '../lib/message_queue'

describe 'app', ->
  {app, messageQueue} = {}

  beforeEach ->
    sinon.stub(librato, 'increment')
    messageQueue = sinon.createStubInstance MessageQueue
    app = appBuilder librato, messageQueue

  afterEach ->
    librato.increment.restore()

  describe 'a POST with two log lines', ->
    {res} = {}

    beforeEach (done) ->
      chai.request(app)
        .post '/drain'
        .send LOG_DATA
        .end (err, _res) ->
          res = _res
          done(err)

    it 'enqueues two messages', ->
      expect(messageQueue.push).to.have.been.calledTwice
      expect(messageQueue.push).to.have.been.calledWithMatch name: 'www', appInstance: 'production'
      expect(messageQueue.push).to.have.been.calledWithMatch msg: 'sample#memory_total=190.64MB'

    it 'returns 200', ->
      expect(res.statusCode).to.equal 200

    it 'respects Heroku header wishes', ->
      expect(res.headers['content-length']).to.equal '0'
      expect(res.headers['connection']).to.equal 'close'

  describe 'two POSTs with the same Logplex-Frame-Id', ->

    it 'logs one set of messages'

    it 'always returns 200'

LOG_DATA = '''
  Dec 18 00:50:48 23.20.136.26 483 <13>1 2013-12-18T00:50:49.193368+00:00 d.1077786c-2728-483f-911f-89a0ef249867 app web.1 - - {"name":"www","appInstance":"production"}
  Dec 18 00:50:48 23.20.136.26 485 <13>1 2013-12-18T00:50:49.194368+00:00 d.1077786c-2728-483f-911f-89a0ef249867 heroku router - - sample#memory_total=190.64MB

'''
