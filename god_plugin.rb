require "XMPP"

module God
  module Contacts

    #Notifier used by God
    #Uses XMPPBot to send messages
    class XmppBot < Contact

      class << self
        attr_accessor :settings, :format
      end

      self.format = lambda do |message, priority, category, host|
        text = "\nMessage: #{message}\n"
        text += "Host: #{host}\n" if host
        text += "Priority: #{priority}\n" if priority
        text += "Category: #{category}\n" if category
        return text
      end

      def valid?
        true
      end

      #alerts contact of event
      #the message is passed to the remote XMPPBot with DRb
      def notify(message, time, priority, category, host)
        begin
          @xmpp.send_message_all(XmppBot.format.call(message, priority, category, host))
          self.info = "sent jabber message"
        rescue => e
          puts e.message
          puts e.backtrace.join("\n")
          self.info = "failed to send jabber message: #{e.message}"
        end
      end

      #setsup a connection with the XMPPBot
      #should be called when setting up the contact in the monitor file
      def connect host, port
        @handler ||= XMPPBot::GodMessageHandler.new(God)
        @xmpp = XMPPBot.connect(host, port, @handler)
      end

    end
  end
end

module XMPPBot

  #Special MessageHandler for usage with God
  class GodMessageHandler < MessageHandler

    @@controls = /start|monitor|restart|stop|unmonitor|remove/
    @@control_messages = {"start" => "Starting", "monitor" => "Monitoring", "restart" => "Restarting", "stop" => "Stopping", "unmonitor" => "Unmonitoring", "remove" => "Removing"}
    @@commands = {:status => "status: returns status of all tasks",
                  :controls => "start|monitor|restart|stop|unmonitor|remove <taskname>: performs action on task",
                  :controlsall => "startall|stopall|restartall <groupnames>: starts|stops|restarts all tasks (of groups when given)"}

    #Stores God object to interface with God
    def initialize god
      @god = god
      @threads = {}
      @level = :viewer
    end

    #process message/command
    def handle from, message
      begin
        command, *rest = message.split(" ")
        task = rest[0]
        case command
        when "status"
          [:return, print_tasks]
        when 'startall'
          [:all, "[#{from}]#{start_all(from, rest)}"]
        when 'restartall'
          [:all, "[#{from}]#{restart_all from, rest}"]
        when "stopall"
          [:all, "[#{from}]#{stop_all from, rest}"]
        when @@controls
          control from, task, command
        else
          [:return, "Unknown command: #{message}.\nUse help to view commands"]
        end
      rescue => e
        [:return, "Error occurred #{e.message}"]
      end
    end

    #returns specific commands for this MessageHandler
    def commands
      com = ""
      @@commands.each do |command, help|
        com << help << "\n"
      end
      com
    end

    #Stops all tasks and shuts down God
    def terminate
      begin
        @threads[Thread.new do
          @god.stop_all
          @god.terminate
        end] = Time.now
        check_threads
      rescue
        #connection closed exception, because:
        #   "Terminate never returns because the process will no longer exist! "
      end
    end

    private

    #starts all tasks
    # => when groups is provided, all tasks in these groups will be started
    def start_all from, groups=[]
      tasks(groups).each do |t|
        exe_control t, 'start'
      end
      "Starting all tasks..."
    end

    #restarts all tasks
    # => when groups is provided, all tasks in these groups will be restarted
    def restart_all from, groups=[]
      tasks(groups).each do |t|
        exe_control t, 'restart'
      end
      "Restarting all tasks..."
    end

    #stops all tasks
    # => when groups is provided, all tasks in these groups will be stopped
    def stop_all from, groups=[]
      if !groups.empty?
        tasks(groups).each do |t|
          exe_control t, 'stop'
        end
        "#{tasks(groups).join(" ")}"
      else
        @threads[Thread.new do
          @god.stop_all
        end] = Time.now
        check_threads
      end
      "Stopping all tasks#{" [#{groups.join(", ")}]" if !groups.empty?}..."
    end

    #returns all tasks registered with God
    def print_tasks
      watches = {}
      @god.status.each do |name, status|
        g = status[:group] || ''
        unless watches.has_key?(g)
          watches[g] = {}
        end
        watches[g][name] = status
      end

      m = ""

      watches.keys.sort.each do |group|
        m << "#{group}:\n" unless group.empty?
        watches[group].keys.sort.each do |name|
          state = watches[group][name][:state]
          m << "  " unless group.empty?
          m << "#{name}: #{state}\n"
        end
      end

      m
    end

    #run a command in God
    #is run in a new thread so the XMPPBot wouldn't hang
    def control from, task, command
      return [:return, "No such task"] if !exe_control task, command
      [:all, "[#{from}]#{control_message command, task}"]
    end

    def exe_control task, command
      return false if !exists_task? task
      @threads[Thread.new do
          @god.control task, command
        end] = Time.now
      check_threads
      true
    end

    #returns array of tasks
    # => when groups is provided, returns all tasks in groups
    def tasks groups=[]
      if groups.empty?
        @god.status.to_a.map{|e| e[0]}
      else
        t = []
        @god.status.each do |name, status|
          g = status[:group] || ''
          t << name if groups.include?(g)
        end
        t
      end
    end

    #checks if task is known by God
    def exists_task? task
      tasks.include? task
    end

    #removes dead and kills overdue threads
    def check_threads
      @threads.delete_if do |t, time|
        stat = t.status
        if stat
          t.kill if Time.now - time > 20
          false
        else
          true
        end
      end
    end

    #returns appropriate message for executed control
    def control_message c, t
      "#{@@control_messages[c]} #{t}..."
    end

  end

end

#To make is possible to pass God over DRb
God.extend(DRbUndumped)
