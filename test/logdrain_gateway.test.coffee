{expect, sinon} = require './test_helper'

librato = require 'librato-node'

logdrainGateway = require '../lib/logdrain_gateway'

describe 'logdrain gateway', ->

  beforeEach ->
    sinon.stub(librato, 'increment')
    sinon.stub(logdrainGateway, 'emit')

  afterEach ->
    librato.increment.restore()
    logdrainGateway.emit.restore()

  describe 'a json log', ->
    beforeEach ->
      logdrainGateway.write 'Dec 18 00:50:48 23.20.136.26 483 <13>1 2013-12-18T00:50:49.193368+00:00 d.1077786c-2728-483f-911f-89a0ef249867 app web.1 - - {"name":"www","appInstance":"production"}\n'

    it 'emits json', ->
      expect(logdrainGateway.emit).to.have.been.calledWithMatch 'data', name: 'www', appInstance: 'production'

  describe 'a logfmt log', ->

    beforeEach ->
      logdrainGateway.write 'Dec 18 00:50:48 23.20.136.26 485 <13>1 2013-12-18T00:50:49.194368+00:00 d.1077786c-2728-483f-911f-89a0ef249867 heroku router - - sample#memory_total=190.64MB\n'

    it 'emits json', ->
      expect(logdrainGateway.emit).to.have.been.calledWithMatch 'data', msg: 'sample#memory_total=190.64MB'

