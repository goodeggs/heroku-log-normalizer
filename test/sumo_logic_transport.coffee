{expect, sinon} = require './test_helper'
nock = require 'nock'
librato = require 'librato-node'

SumoLogicTransport = require '../lib/sumo_logic_transport'

describe 'SumoLogicTransport', ->
  {transport} = {}

  beforeEach ->
    sinon.stub librato, 'increment'
    sinon.stub librato, 'timing'
    transport = new SumoLogicTransport 'https://collectors.sumologic.com/receiver/v1/http/foobar', librato

  afterEach ->
    librato.increment.restore()
    librato.timing.restore()

  describe 'sending one message', ->
    {scope} = {}

    beforeEach (done) ->
      scope = nock 'https://collectors.sumologic.com'
        .post '/receiver/v1/http/foobar', '{"foo":1}'
        .reply 200
      transport.send [{foo: 1}], done

    afterEach ->
      nock.cleanAll()

    it 'posts to sumo logic', ->
      scope.done()
      
    it 'records stats', ->
      expect(librato.increment).to.have.been.calledWith 'sumo_logic.count'
      expect(librato.timing).to.have.been.calledWithMatch 'sumo_logic.time', sinon.match.number
      expect(librato.timing).to.have.been.calledWith 'sumo_logic.size', 9

  describe 'sending two messages', ->
    {scope} = {}

    beforeEach (done) ->
      scope = nock 'https://collectors.sumologic.com'
        .post '/receiver/v1/http/foobar', '{"foo":1}\r\n{"foo":2}'
        .reply 200
      transport.send [{foo: 1}, {foo: 2}], done

    afterEach ->
      nock.cleanAll()

    it 'posts to sumo logic', ->
      scope.done()


