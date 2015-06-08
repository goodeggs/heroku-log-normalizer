Transport = require './transport'

class ConsoleTransport extends Transport

  constructor: ->
    super 'console', null # no stats

  send: (messages, cb) ->
    console.log message for message in messages
    process.nextTick ->
      cb null, responseTime: 0, size: 0

module.exports = ConsoleTransport

