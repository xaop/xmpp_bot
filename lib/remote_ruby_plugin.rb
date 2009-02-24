require "XMPP"

module XMPPBot

  class RemoteRuby < MessageHandler

    def initialize

    end

    def handle from, message
      [:return, begin
          eval(message).to_s
      rescue => e
        e.message
      end]
    end

  end

end