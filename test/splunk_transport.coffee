{expect, sinon} = require './test_helper'
nock = require 'nock'
librato = require 'librato-node'

SplunkTransport = require '../lib/splunk_transport'

describe 'SplunkTransport', ->
  {transport} = {}

  beforeEach ->
    sinon.stub librato, 'increment'
    sinon.stub librato, 'timing'
    transport = new SplunkTransport 'https://x:y@splunkstorm.com/1/http/input?token=foobar', librato

  afterEach ->
    librato.increment.restore()
    librato.timing.restore()

  after ->
    nock.restore()

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

