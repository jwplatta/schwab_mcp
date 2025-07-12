# frozen_string_literal: true

require "logger"

module SchwabMCP
  class Logger
    @instance = nil

    class << self
      def instance
        @instance ||= create_logger
      end

      def debug(message)
        instance.debug(message) if debug_enabled?
      end

      def info(message)
        instance.info(message)
      end

      def warn(message)
        instance.warn(message)
      end

      def error(message)
        instance.error(message)
      end

      def fatal(message)
        instance.fatal(message)
      end

      private

      def create_logger
        if ENV['LOGFILE'] && !ENV['LOGFILE'].empty?
          max_size = (ENV['LOG_MAX_SIZE'] || 10 * 1024 * 1024).to_i
          max_files = (ENV['LOG_MAX_FILES'] || 5).to_i
          logger = ::Logger.new(ENV['LOGFILE'], max_files, max_size)
        else
          logger = ::Logger.new($stderr)
        end

        logger.level = debug_enabled? ? ::Logger::DEBUG : ::Logger::INFO
        logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%H:%M:%S')}] SCHWAB_MCP #{severity}: #{msg}\n"
        end
        logger
      end

      def debug_enabled?
        ENV['DEBUG'] == 'true' || ENV['LOG_LEVEL'] == 'DEBUG'
      end
    end
  end
end
