{expect, sinon} = require './test_helper'
fs = require 'fs'
path = require 'path'
herokuSyslogStream = require '../lib/heroku_syslog_stream'

describe 'herokuSyslogStream', ->

  describe 'a single message', ->
    {log} = {}

    beforeEach ->
      log = fs.createReadStream path.join(__dirname, 'fixtures/single.log')

    it 'extracts messages', (done) ->
      onData = sinon.spy()
      stream = herokuSyslogStream()
      stream.on 'data', onData
      log.pipe(stream)
      stream.on 'end', ->
        expect(onData.callCount).to.equal 1
        expect(onData.getCall(0).args[0]).to.equal '<45>1 2015-05-09T20:21:25.608433+00:00 host heroku web.1 - State changed from starting to crashed\n'
        done()

  describe 'a multiple messages including a wrapped line', ->
    {splitLog} = {}

    beforeEach ->
      splitLog = fs.createReadStream path.join(__dirname, 'fixtures/split.log')

    it 'extracts messages', (done) ->
      onData = sinon.spy()
      stream = herokuSyslogStream()
      stream.on 'data', onData
      splitLog.pipe(stream)
      stream.on 'end', ->
        expect(onData.callCount).to.equal 3
        expect(onData.getCall(0).args[0]).to.equal '<172>1 2015-05-09T20:21:24+00:00 host heroku logplex - Error L10 (output buffer overflow): 1 messages dropped since 2015-05-09T20:19:03+00:00.'
        done()

