# CogServer main entry point
# This provides a standalone executable for running the CogServer

require "./cogserver"

module CogServer
  # Main entry point for command-line usage
  def self.main(args : Array(String) = ARGV)
    options = parse_options(args)
    return unless options

    puts "CogServer #{VERSION} - OpenCog Network Server"

    # Initialize the system before accepting remote requests.
    CogServer.initialize
    server = CogServer::Server.new(options[:host], options[:port], options[:ws_port])

    # Signal handlers only request shutdown. The main loop observes `running?`
    # and returns through `ensure`, so cleanup also occurs on non-signal errors.
    Signal::INT.trap do
      puts "\nShutting down CogServer..."
      server.stop
    end

    Signal::TERM.trap do
      puts "\nShutting down CogServer..."
      server.stop
    end

    begin
      server.start

      puts "\nCogServer is running. Press Ctrl+C to stop."
      puts "Telnet interface: telnet #{options[:host]} #{options[:port]}"
      puts "HTTP API: http://#{options[:host]}:#{options[:ws_port]}"
      puts "Status: http://#{options[:host]}:#{options[:ws_port]}/status"

      # Keep the main fiber alive until a signal requests shutdown.
      while server.running?
        sleep 1.second
      end
    ensure
      server.stop if server.running?
    end
  end

  # Parse CLI options without starting a listener. Returning nil makes malformed
  # invocations safe for library users as well as executable entry points.
  def self.parse_options(args : Array(String)) : NamedTuple(host: String, port: Int32, ws_port: Int32)?
    host = CogServer::DEFAULT_HOST
    port = CogServer::DEFAULT_PORT
    ws_port = CogServer::DEFAULT_WS_PORT

    i = 0
    while i < args.size
      case args[i]
      when "--host", "-h"
        value = args[i + 1]?
        return invalid_option("Missing host after #{args[i]}") unless value && !value.empty?

        host = value
        i += 2
      when "--port", "-p"
        value = args[i + 1]?
        return invalid_option("Missing port after #{args[i]}") unless value

        parsed_port = parse_port(value, args[i])
        return unless parsed_port

        port = parsed_port
        i += 2
      when "--ws-port", "-w"
        value = args[i + 1]?
        return invalid_option("Missing WebSocket/HTTP port after #{args[i]}") unless value

        parsed_port = parse_port(value, args[i])
        return unless parsed_port

        ws_port = parsed_port
        i += 2
      when "--help"
        print_usage
        return nil
      else
        return invalid_option("Unknown option: #{args[i]}")
      end
    end

    return invalid_option("Telnet and WebSocket/HTTP ports must differ") if port == ws_port

    {host: host, port: port, ws_port: ws_port}
  end

  private def self.parse_port(value : String, option : String) : Int32?
    port = value.to_i?
    return invalid_option("Invalid port for #{option}: #{value}") unless port && port.in?(1..65_535)

    port
  end

  private def self.invalid_option(message : String) : Nil
    puts message
    print_usage
  end

  private def self.print_usage
    puts <<-USAGE
    Usage: cogserver [options]

    Options:
      --host, -h HOST      Server host (default: #{DEFAULT_HOST})
      --port, -p PORT      Telnet port (default: #{DEFAULT_PORT})
      --ws-port, -w PORT   WebSocket/HTTP port (default: #{DEFAULT_WS_PORT})
      --help               Show this help message

    Examples:
      cogserver                           # Start with default settings
      cogserver --host 0.0.0.0 --port 17001
      cogserver -h localhost -p 17002 -w 18081
    USAGE
  end
end
