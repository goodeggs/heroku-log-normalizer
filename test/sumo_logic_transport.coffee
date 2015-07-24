{expect, sinon} = require './test_helper'
nock = require 'nock'
librato = require 'librato-node'

SumoLogicTransport = require '../src/sumo_logic_transport'

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
      scope = nock('https://collectors.sumologic.com', {reqheaders: {'Content-Encoding': 'gzip'}})
        .post '/receiver/v1/http/foobar', '1f8b0800000000000003ab562ac9cc4d2d2e49cc2d50b2523232303455d2514acbcf57b232ac0500982d76bf1c000000'
        .reply 200
      transport.send [{foo: 1, timestamp: '2015'}], done

    afterEach ->
      nock.cleanAll()

    it 'posts to sumo logic and moves timestamp to the front of the message', ->
      scope.done()
      
    it 'records stats', ->
      expect(librato.increment).to.have.been.calledWith 'sumo_logic.count'
      expect(librato.timing).to.have.been.calledWithMatch 'sumo_logic.time', sinon.match.number
      expect(librato.timing).to.have.been.calledWith 'sumo_logic.size', 48

  describe 'sending two messages', ->
    {scope} = {}

    beforeEach (done) ->
      scope = nock('https://collectors.sumologic.com', {reqheaders: {'Content-Encoding': 'gzip'}})
        .post '/receiver/v1/http/foobar', '1f8b0800000000000003ab564acbcf57b232ace5e5aa86308d6a0129eb308d14000000'
        .reply 200
      transport.send [{foo: 1}, {foo: 2}], done

    afterEach ->
      nock.cleanAll()

    it 'posts to sumo logic', ->
      scope.done()


