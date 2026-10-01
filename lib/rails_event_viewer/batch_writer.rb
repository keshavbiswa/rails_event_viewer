module RailsEventViewer
  class BatchWriter
    include Logging

    MAX_ATTEMPTS = 3
    LOGGED_EVENTS = 10

    attr_reader :failed_attempts

    def initialize(buffer)
      @buffer = buffer
      reset
    end

    def reset
      @failed_attempts = 0
      @strikes = Hash.new(0)
    end

    def write(events, split: true)
      RailsEventViewer.adapter.write_events(events)
      @buffer.commit(events)
      forget(events)
      @failed_attempts = 0
      true
    rescue => e
      log_error("[RailsEventViewer] Failed to write #{events.size} events: #{e.message}")
      @failed_attempts += 1
      return write_individually(events) if split && @failed_attempts >= MAX_ATTEMPTS

      @buffer.revert(events)
      false
    end

    def forget(events)
      events.each { |event| @strikes.delete(event) } unless @strikes.empty?
    end

    private

    def write_individually(events)
      written = []
      rejected = []
      events.each do |event|
        (write_one(event) ? written : rejected) << event
        break if written.empty? && rejected.size >= MAX_ATTEMPTS
      end

      if written.empty?
        @buffer.revert(events)
        return false
      end

      rejected.each { |event| @strikes[event] += 1 }
      dead, retry_later = rejected.partition { |event| @strikes[event] >= MAX_ATTEMPTS }
      forget(written + dead)

      @buffer.commit(written)
      @buffer.revert(retry_later) if retry_later.any?
      give_up(dead) if dead.any?
      @failed_attempts = retry_later.any? ? MAX_ATTEMPTS - 1 : 0
      true
    end

    def give_up(events)
      names = events.first(LOGGED_EVENTS).map { |event| event[:name] }.join(", ")
      log_error("[RailsEventViewer] Gave up on #{events.size} events the adapter rejected #{MAX_ATTEMPTS} times (#{@last_rejection}): #{names}")
      @buffer.dead(events)
    end

    def write_one(event)
      RailsEventViewer.adapter.write_events([event])
      true
    rescue => e
      @last_rejection = e.message
      false
    end
  end
end
