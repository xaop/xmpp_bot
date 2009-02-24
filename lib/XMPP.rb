require 'rubygems'
require 'xmpp4r'
require 'xmpp4r/roster'
require 'xmpp4r/vcard'
require 'drb'

require 'yaml'

require 'mutex_m'

class Jabber::JID

  ##
  # Convenience method to generate node@domain
  def to_short_s
    s = []
    s << "#@node@" if @node
    s << @domain
    return s.to_s
  end

end


module XMPPBot

  #to connect the service with the bot
  def connect host, port, handler
    DRb.start_service

    #Get remote XMPPBot
    @bot = DRbObject.new_with_uri "druby://#{host}:#{port}"
    #Pass MessageHandler
    @bot.set_handler handler

    @bot
  end

  module_function :connect

  #Abstract class for messagehandling
  class MessageHandler

    include DRbUndumped

    def initialize
    end

    def handle from, message
      [:return, "Received message: #{message}"]
    end

    def commands
      "none"
    end

    def terminate
      exit
    end

  end

  #Simple MessageHandler
  # => looks up message in dictionary and calls associated method on stored object
  class MethodDelegate < MessageHandler

    def initialize obj, dict
      @obj = obj
      @dict = dict
    end

    def handle from, message
      [:return, if @dict[message.to_sym]
          @obj.send(@dict[message.to_sym]).to_s
        else
          "Unknown method"
        end]
    end

  end


  #Bot
  # * Processes incoming and outgoing messages
  #   if necessary delegating them to a handler
  # * Handles subscriptions on servicemessages
  # * Starts/Stops service via messagehandler
  #
  class XMPPBot
    include Mutex_m

    #name: botname
    #config: {:username => username,
    #         :password => password,
    #         :host => host,
    #         :auto_start => true,
    #         :start_delay => seconds,
    #         :start_command => "god -c monitor.rb"}
    #
    #handler: MessageHandler, usually not provided on creation
    #stop_thread: false if scripts needs to keep running after setup of Bot
    #
    def initialize(name, config, handler=nil, stop_thread=true)
      @name            = name
      @start_com       = config[:start_command]
      @handler         = handler
      @friends_sent_to = []
      @friends_online  = {}
      @friends_in_need = []
      @mainthread      = Thread.current

      @config = config

      login(config[:username], config[:password], config[:host])

      listen_for_subscription_requests
      listen_for_presence_notifications
      listen_for_messages

      send_initial_presence

      poll_status if config[:poll_status]

      #keep_alive

      Thread.new do
        sleep(config[:start_delay]) if config[:start_delay]
        start_service if config[:auto_start]
      end

      at_exit do
        begin
          if bool_status
            @handler.terminate
          end
        rescue
          #just quit
        end
      end

      Thread.stop if stop_thread
    end

    #connect to jabberserver
    def login(username, password, host)
      @jid    = Jabber::JID.new("#{username}/#{@name}")
      @client = Jabber::Client.new(@jid)
      @client.connect host
      @client.auth(password)
    end

    #stops serving
    def logout
      @mainthread.wakeup
      @client.close
    end

    #sets messagehandler
    def set_handler handler
      @handler = handler
      @running = true
      change_info
      send_message_all "Service initiated"
    end

    #services that are failing, can remove the handler
    #so the XMPPBot knows something went wrong
    def remove_handler
      @handler = nil
      @running = false
      change_info
      send_message_all "Service terminating..."
    end

    # just a 'keepalive' thread to keep the jabber server in touch
    # sends a presence entity every 30 seconds
    #def keep_alive
      #Thread.new do
       # while true do
        #  @client.send(Jabber::Presence.new.set_status(@status))
         # sleep 30
        #end
      #end
    #end

    #checks every 10 seconds the state of the registered service
    # => this way, the online status of the bot can be altered when
    #    the service goes down
    def poll_status
      Thread.new do
        while true do
          real_stat
          sleep 10
        end
      end
    end

    #notify server of presence
    def send_initial_presence
      @status = "#{@name} is online"
      @client.send(Jabber::Presence.new.set_status(@status))
    end

    #handles subscription requests
    def listen_for_subscription_requests
      @roster   = Jabber::Roster::Helper.new(@client)

      @roster.add_subscription_request_callback do |item, pres|
        if pres.from.domain == @jid.domain
          log "ACCEPTING AUTHORIZATION REQUEST FROM: " + pres.from.to_s
          @roster.accept_subscription(pres.from)
        end
      end
    end

    #handles incoming messages
    def listen_for_messages
      @client.add_message_callback do |m|
        if m.type != :error
          if !@friends_sent_to.include?(m.from)
            send_message m.from, "Welcome to #{@name}\nUse help to view commands"
            @friends_sent_to << m.from
          end

          begin
            case m.body.to_s

              #subscribe to messages from this bot
            when 'yo'
              if @friends_in_need.include? m.from
                send_message m.from, "We already said hello"
              else
                @friends_in_need << m.from
                send_message m.from, "Subscribed to logging"
              end

              #unsubscribe from messages from this bot
            when 'bye'
              if @friends_in_need.delete(m.from)
                send_message m.from, "Unsubscribed from logging"
              else
                send_message m.from, "You say goodbye even before greeting me (yo)!"
              end

              #request status of bot
            when 'cava?'
              send_message m.from, status

              #print available commands
            when 'help'
              send_message m.from, commands

              #run start command on commandline
            when 'init'
              if !bool_status
                send_message_all "[#{m.from.to_short_s}]Initiating...", m.from
                start_service
              else
                send_message m.from, "Already running"
              end

              #terminate via messagehandler
            when 'terminate'
              if bool_status
                send_message_all "[#{m.from.to_short_s}]Terminating...", m.from
                stop_service
              else
                send_message m.from, "Not running"
              end

              #user is probably composing a message
            when ''
              
              #pass message to messagehandler
            else
              puts "RECEIVED: " + m.body.to_s
              if bool_status
                mes = process(m)
                if mes.kind_of? Array
                  to, mes = mes
                else
                  to = :return
                end

                case to
                when :all
                  send_message_all mes, m.from
                when :return
                  send_message m.from, mes
                else
                  send_message to, mes
                end
              else
                send_message m.from, status
                send_message m.from, "Use help to view commands"
              end
            end
          rescue => e
            m = "Exception: #{e.message}"
            log m
            send_message m.from, m
          end
        else
          log [m.type.to_s, m.body].join(": ")
        end
      end
    end

    #handles presence-notifications of friends
    def listen_for_presence_notifications
      @client.add_presence_callback do |m|
        case m.type
        when nil # status: available
          log "PRESENCE: #{m.from.to_short_s} is online"
          @friends_online[m.from.to_short_s] = true
        when :unavailable
          log "PRESENCE: #{m.from.to_short_s} is offline"
          @friends_online[m.from.to_short_s] = false
          @friends_in_need.delete(m.from)
          @friends_sent_to.delete(m.from)
        end
      end
    end

    #obvious
    def send_message(to, message)
      log("Sending message to #{to}")
      msg      = Jabber::Message.new(to, message)
      msg.type = :chat
      @client.send(msg)
    end

    #send the message to all subscripted users
    def send_message_all(message, other=nil)
      @friends_in_need.map { |friend| send_message(friend, message) }
      send_message(other, message) if(other && !@friends_in_need.include?(other))
    end

    #blah
    def change_info()
      if vcard_config = @config[:vcard]
        stat = "#{@name} - #{status}"
        if !@set_photo && vcard_config[:photo]
          @photo = IO::readlines(vcard_config[:photo]).to_s
          @avatar_hash = Digest::SHA1.hexdigest(@photo)
        end
      
        Thread.new do
          vcard = Jabber::Vcard::IqVcard.new({
              'NICKNAME' => @name,
              'FN' => vcard_config['fn'],
              'URL' => vcard_config['url'],
              'PHOTO/TYPE' => 'image/png',
              'PHOTO/BINVAL' => Base64::encode64(@photo)
            })
          Jabber::Vcard::Helper::set(@client, vcard)
        end

        presence = Jabber::Presence.new(:chat, stat)
        x = presence.add(REXML::Element.new('x'))
        x.add_namespace 'vcard-temp:x:update'
        x.add(REXML::Element.new('photo')).text = @avatar_hash
        @client.send presence
        @set_photo = true
        @status = stat
      end
    end

    #obvious
    def log(message)
      puts(message) if Jabber::debug
    end


    private

    def start_service
      @start_com.call if @start_com
    end

    def stop_service
      h = @handler
      @handler = nil
      @running = false
      change_info
      h.terminate
    end

    #returns available commands
    def commands
      c = <<HERE
\nBot Commands
-------------
yo: subscribe to messages of bot
bye: unsubscribe from messages of bot
cava?: ask for status bot
init: start service
terminate: stop service\n
HERE

      if bool_status
        c + @name + " Commands\n----------------\n" + @handler.commands
      else
        c
      end
    end

    #checks availability of services
    def bool_status
      real_stat == :up
    end

    #checks state of services
    # :up : running
    # :just_down : unexpected down
    # :down : already known down
    # :unmonitored : no registered process
    def real_stat
      @handler ? begin
        @handler.to_s
        :up
      rescue
        if @running
          lock
          @running = false
          change_info
          send_message_all "Service went down" 
          unlock
          :just_down
        else
          :down
        end
      end : :unmonitored
    end

    #checks availability of services and returns appropriate message
    def status
      case real_stat
      when :up
        "Service up"
      when :just_down
        "Service down"
      when :down
        "Service down"
      when :unmonitored
        "No process registered for monitoring"
      end
    end

    #pass the message to the messagehandler
    def process m
      @handler.handle(m.from.to_short_s, m.body)
    end

  end

end