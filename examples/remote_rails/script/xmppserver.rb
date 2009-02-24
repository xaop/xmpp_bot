require 'rubygems'
require 'yaml'
require "XMPP"

config   = YAML.load_file(File.join(File.dirname(__FILE__), '../config/xmppconfig.yml'))
username = config['from']['jid']
password = config['from']['password']
host = config['from']['host']

server_host = config['server']['host']
port = config['server']['port']

vcard = config['vcard']

#Start XMPP server with bot
#Messagehandler will be provided by service behind the bot
DRb.start_service("druby://localhost:7778", XMPPBot::XMPPBot.new("RailsApp", {:username => username, :password => password, :host => host, :auto_start => false, :vcard => vcard}, nil, false))

DRb.thread.join