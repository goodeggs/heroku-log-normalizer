librato = require 'librato-node'
os = require 'os'

app = require './app'
MessageQueue = require './message_queue'
syslogToJsonStream = require './syslog_to_json_stream'
logger = require('./logger').child module: 'server'

librato.configure
  email: process.env.LIBRATO_EMAIL
  token: process.env.LIBRATO_TOKEN
  source: os.hostname() # Worker number?
  prefix: 'heroku_log_normalizer.'

librato.start()

if /splunkstorm[.]com/i.test(process.env.TRANSPORT_URI)
  SplunkTransport = require './splunk_transport'
  transport = new SplunkTransport process.env.TRANSPORT_URI, librato
else if /sumologic[.]com/i.test(process.env.TRANSPORT_URI)
  SumoLogicTransport = require './sumo_logic_transport'
  transport = new SumoLogicTransport process.env.TRANSPORT_URI, librato
else
  logger.warn "could not infer transport from TRANSPORT_URI=#{process.env.TRANSPORT_URI}, using stdout"
  ConsoleTransport = require './console_transport'
  transport = new ConsoleTransport

messageQueue = new MessageQueue transport
syslogToJsonStream.on 'data', (data) ->
  messageQueue.push data

app.listen process.env.PORT ? 8000

_exit = do ->
  exited = 0
  (code) ->
    return if exited++ # exit only once
    app.close ->
      logger.warn 'Waiting for message queue to drain...'
      pollInterval = setInterval((-> logger.info "#{messageQueue.length()} messages left to send"), 1000)
      messageQueue.flush ->
        logger.info 'drained!'
        clearInterval pollInterval
        process.exit code

process.on 'SIGINT', do ->
  signalCount = 0
  ->
    code = 127 + 2
    logger.warn 'Got SIGINT.  Exiting.'
    _exit(code)
    if signalCount++ > 0
      process.exit(code)

process.on 'SIGTERM', ->
  logger.warn 'Got SIGTERM.  Exiting.'
  _exit(127 + 15)

