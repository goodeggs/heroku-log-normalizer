{expect, sinon} = require './test_helper'
nock = require 'nock'
librato = require 'librato-node'

SplunkTransport = require '../src/splunk_transport'

describe 'SplunkTransport', ->
  {transport} = {}

  beforeEach ->
    sinon.stub librato, 'increment'
    sinon.stub librato, 'timing'
    transport = new SplunkTransport 'https://x:y@splunkstorm.com/1/http/input?token=foobar', librato

  afterEach ->
    librato.increment.restore()
    librato.timing.restore()

  describe 'sending one message', ->
    {scope} = {}

    beforeEach (done) ->
      scope = nock 'https://splunkstorm.com'
        .post '/1/http/input?token=foobar&sourcetype=json_predefined_timestamp', '{"foo":1}'
        .reply 200
      transport.send [{foo: 1}], done

    afterEach ->
      nock.cleanAll()

    it 'posts to splunk', ->
      scope.done()
      
    it 'records stats', ->
      expect(librato.increment).to.have.been.calledWith 'splunk.count'
      expect(librato.timing).to.have.been.calledWithMatch 'splunk.time', sinon.match.number
      expect(librato.timing).to.have.been.calledWith 'splunk.size', 9

  describe 'sending two messages', ->
    {scope} = {}

    beforeEach (done) ->
      scope = nock 'https://splunkstorm.com'
        .post '/1/http/input?token=foobar&sourcetype=json_predefined_timestamp', '{"foo":1}\r\n{"foo":2}'
          .reply 200
      transport.send [{foo: 1}, {foo: 2}], done

    afterEach ->
      nock.cleanAll()

    it 'posts to splunk', ->
      scope.done()

