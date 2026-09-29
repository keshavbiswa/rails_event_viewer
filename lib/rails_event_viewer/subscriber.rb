# frozen_string_literal: true

module RailsEventViewer
  class Subscriber
    NANOSECONDS_PER_SECOND = 1_000_000_000.0
    SHUTDOWN_TIMEOUT_SECONDS = 5
    ACTION_CABLE_CHANNEL = "rails_event_viewer:events"

    def initialize
      @buffer = Queue.new
      @mutex = Mutex.new
      @flusher_thread = nil
      @shutdown_requested = false
      @pid = Process.pid

      ensure_flusher_thread!
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
      broadcast_events(events_to_write)
    end

    def stop!
      @mutex.synchronize do
        @shutdown_requested = true
      end

      if @flusher_thread&.alive?
        @flusher_thread.wakeup rescue nil
        @flusher_thread.join(SHUTDOWN_TIMEOUT_SECONDS)
      end

      @mutex.synchronize do
        @flusher_thread = nil
      end

      flush!
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
          @flusher_thread = nil
          @shutdown_requested = false
        end
      end
      ensure_flusher_thread!
    end

    def drain_buffer
      events = []
      loop { events << @buffer.pop(true) }
    rescue ThreadError
      events
    end

    def buffer_event(entry)
      @buffer << entry
      ensure_flusher_thread!

      flush! if @buffer.size >= RailsEventViewer.buffer_size
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
      log_info("[RailsEventViewer] Flusher thread started (PID: #{Process.pid})")

      until shutdown_requested?
        begin
          sleep(RailsEventViewer.flush_interval)
          flush! unless @buffer.empty?
        rescue => e
          log_error("[RailsEventViewer] Flusher error: #{e.message}")
        end
      end

      log_info("[RailsEventViewer] Flusher thread stopped (PID: #{Process.pid})")
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

    def broadcast_events(events)
      return unless defined?(ActionCable)
      return unless events.any?

      ActionCable.server.broadcast(
        ACTION_CABLE_CHANNEL,
        {
          action: "new_events",
          count: events.size,
          events: events.map { |e| { name: e[:name], occurred_at: e[:occurred_at]&.iso8601 } }
        }
      )
    rescue => e
      log_error("[RailsEventViewer] Broadcast error: #{e.message}")
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

    def log_info(message)
      effective_logger&.info(message)
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
