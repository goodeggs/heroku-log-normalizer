SyslogParser = require('glossy').Parse
librato = require 'librato-node'
through = require 'through'
combine = require 'stream-combiner'
qs = require 'querystring'

syslogMessageToJSON = (syslogMessage) ->

  # pull explicit options off the front of the line
  [opts, syslogMessage...] = syslogMessage.split('!')
  opts = qs.parse opts
  syslogMessage = syslogMessage.join('!') # reassemble the rest

  parsed = SyslogParser.parse syslogMessage

  # try parsing the message as JSON first, since most of our app logs are JSON
  result = try JSON.parse(parsed.message)
  # if that fails, use the raw message
  result ?= msg: parsed.message, timestamp: new Date().toISOString()

  # make time field match splunk's expectation of timestamp
  result.timestamp ?= result.time or parsed.time.toISOString()
  delete result.time

  # clean some fields from the syslog header, and add it at syslog
  delete parsed.originalMessage
  delete parsed.message
  result.syslog = parsed

  # apply (as defaults) any options we were provided
  result[k] ?= v for k, v of opts

  return result

parseStream = through (line) ->
  librato.increment 'incoming'
  @queue syslogMessageToJSON(line.toString())

module.exports = parseStream

