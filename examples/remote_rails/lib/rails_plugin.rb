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

DRb.start_service
XMPP = DRbObject.new_with_uri "druby://localhost:7778"
XMPP.set_handler(XMPPBot::MethodDelegate.new(XMPPTester.new(Product), {:list => :list}))