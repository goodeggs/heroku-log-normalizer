{expect, sinon} = require './test_helper'
librato = require 'librato-node'

MessageQueue = require '../lib/message_queue'
Transport = require '../lib/transport'

describe 'MessageQueue', ->
  {transport, queue} = {}

  beforeEach ->
    sinon.stub librato, 'increment'
    sinon.stub librato, 'timing'
    transport = sinon.createStubInstance Transport
    transport.send.yields(null, {responseTime: 500, size: 1024})
    queue = new MessageQueue transport, false

  afterEach ->
    librato.increment.restore()
    librato.timing.restore()

  describe 'with no messages', ->
    it 'length is 0', ->
      expect(queue.length()).to.equal 0

  describe 'pushing one message', ->
    {scope} = {}

    beforeEach (done) ->
      queue.push {foo: 1}
      queue.flush done

    it 'sends the message', ->
      expect(transport.send).to.have.been.calledWith [{foo: 1}]

    it 'calls stats', ->
      expect(librato.increment).to.have.been.calledWith 'outgoing', 1

  describe 'a flood of messages', ->

    beforeEach (done) ->
      queue.push {foo: 1}
      setTimeout ->
        queue.push {foo: 2}
        queue.push {foo: 3}
        queue.push {foo: 4}
        queue.flush done
      , 10

    it 'sends the messages', ->
      expect(transport.send).to.have.been.calledTwice
      expect(transport.send.firstCall.args[0]).to.eql [{foo: 1}]
      expect(transport.send.secondCall.args[0]).to.eql [{foo: 2}, {foo: 3}, {foo: 4}]

    it 'calls stats', ->
      expect(librato.increment).to.have.been.calledWith 'outgoing', 1
      expect(librato.increment).to.have.been.calledWith 'outgoing', 3

  describe '::_worker', ->
    {completeWork} = {}

    beforeEach ->
      completeWork = null
      sinon.stub queue, '_send', (messages, cb) -> completeWork = cb
      sinon.stub GLOBAL, 'setTimeout'
      queue.throttle = true

    afterEach ->
      queue._send.restore()
      GLOBAL.setTimeout.restore()
      queue.throttle = false


    describe 'when queue is low', ->
      beforeEach ->
        MessageQueue.MAX_LOG_LINE_BATCH_SIZE = 100
        sinon.stub(queue._queue, 'length').returns(10)

      it 'waits 5 seconds', ->
        queue._worker 'data', ->
        completeWork()
        expect(setTimeout).to.have.been.calledWith sinon.match.func, 5000

    describe 'when transport request is faster than 1 second', ->
      beforeEach ->
        MessageQueue.MAX_LOG_LINE_BATCH_SIZE = 0
        sinon.stub process, 'hrtime', ->
          [0, 999 * 1e6] # 999 ms

      it 'waits the remainder of 1-second interval before sending another request', (done) ->
        queue._worker 'data', ->
        completeWork()
        expect(setTimeout).to.have.been.calledWith sinon.match.func, 1
        done()

