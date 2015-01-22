{expect} = require 'chai'
nock = require 'nock'
SplunkQueue = require '../lib/splunk_queue'

describe 'SplunkQueue', ->
  {queue, stats} = {}

  beforeEach ->
    stats = []
    queue = new SplunkQueue 'https://x:y@splunkstorm.com/1/http/input?token=foobar'
    queue.on 'stat', (stat, val) ->
      stats.push [stat, val]

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

    it 'emits stats', ->
      expect(stats).to.eql [['outgoing', 1]]

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

    it 'emits stats', ->
      expect(stats).to.eql [['outgoing', 1], ['outgoing', 3]]

