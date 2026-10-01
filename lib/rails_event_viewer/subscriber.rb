# frozen_string_literal: true

module RailsEventViewer
  class Subscriber
    NANOSECONDS_PER_SECOND = 1_000_000_000.0
    SHUTDOWN_TIMEOUT_SECONDS = 5
    MAX_BUFFER_MULTIPLIER = 10

    def initialize
      @buffer = Queue.new
      @flush_requests = Queue.new
      @mutex = Mutex.new
      @flusher_thread = nil
      @shutdown_requested = false
      @dropped_count = 0
      @pid = Process.pid
    end

    def emit(event)
      handle_fork_if_needed

      return unless should_capture?(event)
      return if sampled_out?

      entry = build_entry(event)

      if RailsEventViewer.async
        buffer_event(entry)
      else
        write_immediately([entry])
      end
    rescue => e
      handle_error(e, event)
    end

    def flush!
      return if @buffer.empty?

      events_to_write = drain_buffer

      return if events_to_write.empty?

      write_immediately(events_to_write)
      report_dropped_events
    end

    def stop!
      @mutex.synchronize do
        @shutdown_requested = true
      end

      if @flusher_thread&.alive?
        @flush_requests << true
        @flusher_thread.join(SHUTDOWN_TIMEOUT_SECONDS)
      end

      @mutex.synchronize do
        @flusher_thread = nil
      end

      flush! until @buffer.empty?
    end

    def running?
      @flusher_thread&.alive? || false
    end

    def buffer_size
      @buffer.size
    end

    private

    def handle_fork_if_needed
      # Threads don't survive forks, so we need to restart the flusher
      @mutex.synchronize do
        if @pid != Process.pid
          @pid = Process.pid
          @buffer = Queue.new
          @flush_requests = Queue.new
          @flusher_thread = nil
          @shutdown_requested = false
          @dropped_count = 0
        end
      end
    end

    def drain_buffer
      events = []
      [@buffer.size, max_buffer_size].min.times { events << @buffer.pop(true) }
      events
    rescue ThreadError
      events
    end

    def buffer_event(entry)
      @buffer << entry
      return flush! if shutdown_requested?

      ensure_flusher_thread!
      drop_oldest_events if @buffer.size > max_buffer_size
      request_flush if @buffer.size >= RailsEventViewer.buffer_size
    end

    def max_buffer_size
      RailsEventViewer.buffer_size * MAX_BUFFER_MULTIPLIER
    end

    def drop_oldest_events
      dropped = 0
      while @buffer.size > max_buffer_size
        @buffer.pop(true)
        dropped += 1
      end
    rescue ThreadError
      nil
    ensure
      @mutex.synchronize { @dropped_count += dropped } if dropped.positive?
    end

    def report_dropped_events
      dropped = @mutex.synchronize { @dropped_count.tap { @dropped_count = 0 } }
      return if dropped.zero?

      effective_logger&.warn("[RailsEventViewer] Dropped #{dropped} events because the buffer was full")
    end

    def request_flush
      @flush_requests << true if @flush_requests.empty?
    end

    def ensure_flusher_thread!
      return unless RailsEventViewer.async

      @mutex.synchronize do
        return if @flusher_thread&.alive?
        return if @shutdown_requested

        @flusher_thread = Thread.new { run_flusher_loop }
      end
    end

    def run_flusher_loop
      effective_logger&.debug("[RailsEventViewer] Flusher thread started (PID: #{Process.pid})")

      until shutdown_requested?
        begin
          @flush_requests.pop(timeout: RailsEventViewer.flush_interval)
          loop do
            flush!
            break if @buffer.size < RailsEventViewer.buffer_size || shutdown_requested?
          end
        rescue => e
          log_error("[RailsEventViewer] Flusher error: #{e.message}")
        end
      end

      effective_logger&.debug("[RailsEventViewer] Flusher thread stopped (PID: #{Process.pid})")
    end

    def shutdown_requested?
      @mutex.synchronize { @shutdown_requested }
    end

    def write_immediately(events)
      return if events.blank?

      RailsEventViewer.adapter.write_events(events)
    rescue => e
      log_error("[RailsEventViewer] Failed to write #{events.size} events: #{e.message}")
    end

    def should_capture?(event)
      return false unless event.is_a?(Hash)
      return false if event[:name].blank?

      name = event[:name].to_s
      return false if ignored?(name)
      return true if RailsEventViewer.captured_events.empty?

      captured?(name)
    end

    def ignored?(name)
      RailsEventViewer.ignored_events.any? do |pattern|
        matches_pattern?(name, pattern)
      end
    end

    def captured?(name)
      RailsEventViewer.captured_events.any? do |pattern|
        matches_pattern?(name, pattern)
      end
    end

    def matches_pattern?(name, pattern)
      case pattern
      when String
        name == pattern
      when Regexp
        name.match?(pattern)
      else
        false
      end
    end

    def sampled_out?
      rate = RailsEventViewer.sample_rate
      return false if rate >= 1.0

      rand > rate
    end

    def build_entry(event)
      timestamp = event[:timestamp]
      occurred_at = if timestamp
        Time.at(timestamp / NANOSECONDS_PER_SECOND)
      else
        Time.current
      end

      {
        name: event[:name],
        payload: serialize_payload(event[:payload]),
        tags: event[:tags] || {},
        context: event[:context] || {},
        source_file: event.dig(:source_location, :filepath),
        source_line: event.dig(:source_location, :lineno),
        source_label: event.dig(:source_location, :label),
        occurred_at: occurred_at
      }
    end

    def serialize_payload(payload)
      case payload
      when Hash
        payload
      when nil
        {}
      else
        if payload.respond_to?(:to_h)
          payload.to_h
        elsif payload.respond_to?(:as_json)
          payload.as_json
        else
          { value: payload.to_s }
        end
      end
    end

    def handle_error(error, event)
      log_error("[RailsEventViewer] Failed to capture event '#{event[:name]}': #{error.message}")
    end

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
