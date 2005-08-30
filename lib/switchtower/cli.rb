require 'optparse'
require 'switchtower'

module SwitchTower
  class CLI
    def self.execute!
      new.execute!
    end

    begin
      if !defined?(USE_TERMIOS) || USE_TERMIOS
        require 'termios'
      else
        raise LoadError
      end

      # Enable or disable stdin echoing to the terminal.
      def echo(enable)
        term = Termios::getattr(STDIN)

        if enable
          term.c_lflag |= (Termios::ECHO | Termios::ICANON)
        else
          term.c_lflag &= ~Termios::ECHO
        end

        Termios::setattr(STDIN, Termios::TCSANOW, term)
      end
    rescue LoadError
      def echo(enable)
      end
    end

    attr_reader :options

    def initialize
      @options = { :verbose => 0, :recipes => [], :actions => [], :vars => {} }

      OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"
        opts.separator ""

        opts.on("-a", "--action ACTION",
          "An action to execute. Multiple actions may",
          "be specified, and are loaded in the given order."
        ) { |value| @options[:actions] << value }

        opts.on("-p", "--password PASSWORD",
          "The password to use when connecting.",
          "(Default: prompt for password)"
        ) { |value| @options[:password] = value }

        opts.on("-P", "--[no-]pretend",
          "Run the task(s), but don't actually connect to or",
          "execute anything on the servers. (For various reasons",
          "this will not necessarily be an accurate depiction",
          "of the work that will actually be performed.",
          "Default: don't pretend.)"
        ) { |value| @options[:pretend] = value }

        opts.on("-r", "--recipe RECIPE",
          "A recipe file to load. Multiple recipes may",
          "be specified, and are loaded in the given order."
        ) { |value| @options[:recipes] << value }

        opts.on("-s", "--set NAME=VALUE",
          "Specify a variable and it's value to set. This",
          "will be set after loading all recipe files."
        ) do |pair|
          name, value = pair.split(/=/)
          @options[:vars][name.to_sym] = value
        end

        opts.on("-v", "--verbose",
          "Specify the verbosity of the output.",
          "May be given multiple times. (Default: silent)"
        ) { @options[:verbose] += 1 }

        opts.separator ""
        opts.on_tail("-h", "--help", "Display this help message") do
          puts opts
          exit
        end
        opts.on_tail("-V", "--version",
          "Display the version info for this utility"
        ) do
          require 'switchtower/version'
          puts "SwitchTower v#{SwitchTower::Version::STRING}"
          exit
        end

        opts.parse!
      end

      abort "You must specify at least one recipe" if @options[:recipes].empty?
      abort "You must specify at least one action" if @options[:actions].empty?

      unless @options.has_key?(:password)
        @options[:password] = Proc.new do
          sync = STDOUT.sync
          begin
            echo false
            STDOUT.sync = true
            print "Password: "
            STDIN.gets.chomp
          ensure
            echo true
            STDOUT.sync = sync
            puts
          end
        end
      end
    end

    def execute!
      config = SwitchTower::Configuration.new
      config.logger.level = options[:verbose]
      config.set :password, options[:password]
      config.set :pretend, options[:pretend]

      config.load "standard" # load the standard recipe definition

      options[:recipes].each { |recipe| config.load(recipe) }
      options[:vars].each { |name, value| config.set(name, value) }

      actor = config.actor
      options[:actions].each { |action| actor.send action }
    end
  end
end
