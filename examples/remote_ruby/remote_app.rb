require 'rubygems'
require 'remote_ruby_plugin'

bot = XMPPBot.connect("localhost", "7778", XMPPBot::RemoteRuby.new)
Thread.new do
  while true
    bot.send_message_all Time.now.to_s
    sleep 10
  end
end.join