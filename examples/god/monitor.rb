require 'rubygems'
require 'yaml'
require 'god_plugin'

RAILS_ROOT = "/Users/username/NetBeansProjects/StandardRailsApp"

config   = YAML.load_file('config.yml')
host = config['server']['host']
port = config['server']['port']
#XmmpBot is a custom contact class for usage with a XMMPBot
God.contact(:xmpp_bot) do |c|
  c.name = 'tim'
  c.connect host, port
end

#Standard god code
(3000..3005).each do |i|
  God.watch do |w|
    w.name = "local-#{i}"
    w.group = (i % 2 == 0) ? "locals1" : "locals2"
    w.interval = 5.seconds # default
    w.start = "mongrel_rails start -c #{RAILS_ROOT} -P #{RAILS_ROOT}/log/mongrel#{i}.pid -p #{i} -d"
    w.stop = "mongrel_rails stop -P #{RAILS_ROOT}/log/mongrel#{i}.pid"
    w.restart = "mongrel_rails restart -P #{RAILS_ROOT}/log/mongrel#{i}.pid"
    w.pid_file = File.join(RAILS_ROOT, "log/mongrel#{i}.pid")

    # clean pid files before start if necessary
    w.behavior(:clean_pid_file)

    # determine the state on startup
    w.transition(:init, { true => :up, false => :start }) do |on|
      on.condition(:process_running) do |c|
        c.running = true
        c.notify = 'tim'
      end
    end

    # determine when process has finished starting
    w.transition([:start, :restart], :up) do |on|
      on.condition(:process_running) do |c|
        c.running = true
        c.notify = 'tim'
      end

      # failsafe
      on.condition(:tries) do |c|
        c.times = 5
        c.transition = :start
        c.notify = 'tim'
      end
    end

    # start if process is not running
    w.transition(:up, :start) do |on|
      on.condition(:process_exits) do |c|
        c.notify = 'tim'
      end
    end

    # restart if memory or cpu is too high
    w.transition(:up, :restart) do |on|
      on.condition(:memory_usage) do |c|
        c.interval = 20
        c.above = 50.megabytes
        c.times = [3, 5]
        c.notify = 'tim'
      end

      on.condition(:cpu_usage) do |c|
        c.interval = 10
        c.above = 10.percent
        c.times = [3, 5]
        c.notify = 'tim'
      end
    end

    # lifecycle
    w.lifecycle do |on|
      on.condition(:flapping) do |c|
        c.to_state = [:start, :restart]
        c.times = 5
        c.within = 5.minute
        c.transition = :unmonitored
        c.retry_in = 10.minutes
        c.retry_times = 5
        c.retry_within = 2.hours
        c.notify = 'tim'
      end
    end
  end
end