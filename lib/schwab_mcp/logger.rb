# frozen_string_literal: true

require "logger"
require "tmpdir"
require_relative "redactor"

module SchwabMCP
  class Logger
    @instance = nil

    class << self
      def instance
        @instance ||= create_logger
      end

      def debug(message)
        instance.debug(Redactor.redact_formatted_text(message)) if debug_enabled?
      end

      def info(message)
        instance.info(Redactor.redact_formatted_text(message))
      end

      def warn(message)
        instance.warn(Redactor.redact_formatted_text(message))
      end

      def error(message)
        instance.error(Redactor.redact_formatted_text(message))
      end

      def fatal(message)
        instance.fatal(Redactor.redact_formatted_text(message))
      end

      private

      def create_logger
        if ENV['LOGFILE'] && !ENV['LOGFILE'].empty?
          max_size = (ENV['LOG_MAX_SIZE'] || 10 * 1024 * 1024).to_i
          max_files = (ENV['LOG_MAX_FILES'] || 5).to_i
          logger = ::Logger.new(ENV['LOGFILE'], max_files, max_size)
        else
          # When running as MCP server, don't log to stderr as it interferes with the protocol
          # Use a default log file instead
          default_log_file = File.join(Dir.tmpdir, 'schwab_mcp.log')
          logger = ::Logger.new(default_log_file)
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
