require 'rubygems'
require 'XMPP'
require 'drb'

class XMPPTester

  def initialize obj
    @obj = obj
  end

  def list
    @obj.all.map { |e| e.name }.join(" ")
  end

end

require 'yaml'

config   = YAML.load_file(File.join(File.dirname(__FILE__), '../config/xmppconfig.yml'))

server_host = config['server']['host']
port = config['server']['port']

DRb.start_service
XMPP = DRbObject.new_with_uri "druby://#{server_host}:#{port}"
XMPP.set_handler(XMPPBot::MethodDelegate.new(XMPPTester.new(Product), {:list => :list}))