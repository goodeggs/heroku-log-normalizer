{expect} = chai = require 'chai'
nock = require 'nock'
sinon = require 'sinon'
chai.use require 'sinon-chai'
librato = require 'librato-node'

MessageQueue = require '../lib/message_queue'

class StatsMock
  constructor: ->
    @stats = []

  increment: (metric, value) ->
    @stats.push [metric, value]

describe 'MessageQueue', ->
  {queue, stats, statsMock} = {}

  beforeEach ->
    stats = []
    sinon.stub librato, 'increment'
    sinon.stub librato, 'timing'
    queue = new MessageQueue 'https://x:y@splunkstorm.com/1/http/input?token=foobar', librato, false

  afterEach ->
    librato.increment.restore()
    librato.timing.restore()

  after ->
    nock.restore()

  describe 'with no messages', ->
    it 'length is 0', ->
      expect(queue.length()).to.equal 0

  describe 'pushing one message', ->
    {scope} = {}

    beforeEach (done) ->
      scope = nock 'https://splunkstorm.com'
        .post '/1/http/input?token=foobar&sourcetype=json_predefined_timestamp', '{"foo":1}'
        .reply 200
      queue.push {foo: 1}
      queue.flush done

    afterEach ->
      nock.cleanAll()

    it 'posts to splunk', ->
      scope.done()

    it 'called stats', ->
      expect(librato.increment).to.have.been.calledWith 'outgoing', 1

  describe 'a flood of messages', ->
    {scope} = {}

    beforeEach (done) ->
      scope = nock 'https://splunkstorm.com'
        .post '/1/http/input?token=foobar&sourcetype=json_predefined_timestamp', '{"foo":1}'
          .reply 200
        .post '/1/http/input?token=foobar&sourcetype=json_predefined_timestamp', '{"foo":2}\r\n{"foo":3}\r\n{"foo":4}'
          .reply 200
      queue.push {foo: 1}
      setTimeout ->
        queue.push {foo: 2}
        queue.push {foo: 3}
        queue.push {foo: 4}
        queue.flush done
      , 10

    afterEach ->
      nock.cleanAll()

    it 'posts to splunk', ->
      scope.done()

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

    describe 'when splunk request is faster than 1 second', ->
      beforeEach ->
        MessageQueue.MAX_LOG_LINE_BATCH_SIZE = 0
        sinon.stub process, 'hrtime', ->
          [0, 999 * 1e6] # 999 ms

      it 'waits the remainder of 1-second interval before sending another request', (done) ->
        queue._worker 'data', ->
        completeWork()
        expect(setTimeout).to.have.been.calledWith sinon.match.func, 1
        done()
