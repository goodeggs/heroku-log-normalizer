bunyan = require 'bunyan'
logger = GLOBAL.logger ?= bunyan.createLogger name: 'heroku_log_normalizer'

if process.env.NODE_ENV is 'test'
  logger.level('warn')

module.exports = logger
