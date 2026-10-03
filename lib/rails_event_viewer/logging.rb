module RailsEventViewer
  module Logging
    private

    def log_error(message)
      RailsEventViewer.effective_logger.error(message)
    end
  end
end
