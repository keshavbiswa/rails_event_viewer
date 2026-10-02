# frozen_string_literal: true

module RailsEventViewer
  class Subscriber
    include Logging

    NANOSECONDS_PER_SECOND = 1_000_000_000.0

    delegate :flush!, :stop!, :running?, to: :@flusher
    delegate :size, to: :@flusher, prefix: :buffer

    def initialize
      @flusher = Flusher.new(RailsEventViewer.buffer)
    end

    def emit(event)
      return unless should_capture?(event)
      return if sampled_out?

      entry = build_entry(event)

      if RailsEventViewer.async
        @flusher.push(entry)
      else
        RailsEventViewer.adapter.write_events([entry])
      end
    rescue => e
      handle_error(e, event)
      raise
    end

    private

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
        payload: snapshot(serialize_payload(event[:payload])),
        tags: snapshot(event[:tags] || {}),
        context: snapshot(event[:context] || {}),
        source_file: event.dig(:source_location, :filepath),
        source_line: event.dig(:source_location, :lineno),
        source_label: event.dig(:source_location, :label),
        occurred_at: occurred_at
      }
    end

    def snapshot(value)
      JSON.parse(JSON.generate(value.as_json), symbolize_names: true)
    rescue SystemStackError, StandardError
      { value: value.inspect }
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
  end
end
