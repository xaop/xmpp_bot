require 'rubygems'
require "XMPP"

config   = YAML.load_file('config-rr.yml')
username = config['from']['jid']
password = config['from']['password']
host = config['from']['host']

server_host = config['server']['host']
port = config['server']['port']

vcard = config['vcard']

#Start XMPP server with bot
#Messagehandler will be provided by service behind the bot
DRb.start_service("druby://#{server_host}:#{port}",
  XMPPBot::XMPPBot.new("RemoteRuby", {:username => username,
                               :password => password,
                               :host => host,
                               :auto_start => true,
                               :start_delay => 5,
                               :start_command => lambda { `ruby remote_app.rb` },
                               :vcard => vcard},
                             nil, false))

DRb.thread.join