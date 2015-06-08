through = require 'through'

###
# Heroku logplex sends us a chunk of messages that look like "142 <175>......', where 142 is the length of the syslog message that follows it.
# Thus, we use this stream to split up the actual syslog messages using the message length they give us.
###

module.exports = ->
  inLength = false
  length = ''
  messageRemaining = 0
  message = ''

  through (data) ->
    for charCode in data
      char = String.fromCharCode(charCode)
      switch true
        when messageRemaining > 0
          message += char
          messageRemaining--
        when '0' <= char <= '9'
          inLength = true
          length += char
        when inLength # the space between length and syslog message
          inLength = false
          messageRemaining = parseInt(length)
          length = ''

      if messageRemaining is 0 and message.length
        @emit 'data', message
        message = ''

