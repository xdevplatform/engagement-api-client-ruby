module AppLogger

  require 'logging'
  require 'yaml'

  class << self
    attr_accessor :logger,
                  :config_file,
                  :name, 
                  :log_path,
                  :warn_level,
                  :size, 
                  :keep, 
                  :roll_by,
                  :verbose
                  

    def set_config(verbose=nil)

      if verbose.nil?
         @verbose = verbose
      else
         @verbose = true #Choice of being noisy by default for example code...
      end
      
      if @config_file.nil?
        @log_path = "../log/"
        Dir.mkdir("#{@log_path}") unless File.exist?("#{@log_path}")

        @name = 'app.log'
        @warn_level = 'info'
        @size = 10 #MB
        @keep = 2
       
      else
        config = {}
        config = YAML.load_file(@config_file)
        @name = config['logging']['name']
        @log_path = config['logging']['log_path']
        Dir.mkdir("#{@log_path}") unless File.exist?("#{@log_path}")
        @warn_level = config['logging']['warn_level']
        @size = config['logging']['size']
        @keep = config['logging']['keep']
      end
    end
    
    def set_logger
      Logging.init :debug, :info, :warn, :error, :critical, :fatal
      @logger = Logging.logger("#{@log_path}/#{@name}")
      @logger.level = @warn_level

      layout = Logging.layouts.pattern(:pattern => '[%d] %-5l: %m\n')

      #Always write to a rolling file.
      default_appender = Logging::Appenders::RollingFile.new 'default', \
        :filename => "#{@log_path}/#{@name}", :size => (@size * 1024), :keep => @keep, :safe => true, :layout => layout

      #@logger.add_appenders(Logging.appenders.stdout)

      @logger
      
    end

    def log
      if @logger.nil?
        set_logger()
        if @config_file.nil?
          log.info("No logging configuration provided, using defaults and logging to #{@log_path}#{@name}")
        end
      end

      @logger
    end
    
    
    #Wrappers log functions that honor verbose settings and can write to Standard Out.
    
    def log_info(msg, verbose = nil)
      
      verbose = @verbose if verbose.nil?

      AppLogger.log.info(msg)
      puts msg if verbose
    end

    def log_warn(msg, verbose = nil)

      verbose = @verbose if verbose.nil?

      AppLogger.log.warn(msg)
      puts msg if verbose
    end

    def log_debug(msg, verbose = nil)

      verbose = @verbose if verbose.nil?

      AppLogger.log.debug(msg)
      puts msg if verbose
    end
    
    
    def log_error(msg)
      AppLogger.log.error(msg)
      puts msg #Always shout about errors.
    end

  end #class  
  
end # module

  
if __FILE__ == $0 #This script code is executed when running this file.
  
  include AppLogger
  
  AppLogger.config_file = '../config/app_settings.yaml'
  AppLogger.set_config
  AppLogger.set_logger
  
  
  AppLogger.log.info "Logging information."
  AppLogger.log.debug "Logging debug message."

end