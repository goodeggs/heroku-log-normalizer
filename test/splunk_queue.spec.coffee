{expect} = chai = require 'chai'
nock = require 'nock'
sinon = require 'sinon'
chai.use require 'sinon-chai'
librato = require 'librato-node'

SplunkQueue = require '../lib/splunk_queue'

class StatsMock
  constructor: ->
    @stats = []

  increment: (metric, value) ->
    @stats.push [metric, value]

describe 'SplunkQueue', ->
  {queue, stats, statsMock} = {}

  beforeEach ->
    stats = []
    sinon.stub librato, 'increment'
    queue = new SplunkQueue 'https://x:y@splunkstorm.com/1/http/input?token=foobar', librato

  afterEach ->
    librato.increment.restore()

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
      , 0

    afterEach ->
      nock.cleanAll()

    it 'posts to splunk', ->
      scope.done()

    it 'calls stats', ->
      expect(librato.increment).to.have.been.calledWith 'outgoing', 1
      expect(librato.increment).to.have.been.calledWith 'outgoing', 3
