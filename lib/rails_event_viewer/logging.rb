module RailsEventViewer
  module Logging
    private

    def log_error(message)
      logger = effective_logger

      if logger
        logger.error(message)
      else
        warn message
      end
    end

    def effective_logger
      RailsEventViewer.logger || (defined?(Rails) && Rails.logger)
    end
  end
end
