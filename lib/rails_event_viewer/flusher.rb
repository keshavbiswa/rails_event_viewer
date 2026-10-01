module RailsEventViewer
  class Flusher
    include Logging

    SHUTDOWN_TIMEOUT_SECONDS = 5
    MAX_BUFFER_MULTIPLIER = 10

    def initialize(buffer)
      @buffer = buffer
      @writer = BatchWriter.new(buffer)
      @flush_requests = Queue.new
      @mutex = Mutex.new
      @thread = nil
      @shutdown_requested = false
      @dropped_count = 0
      @pid = Process.pid
    end

    def push(entry)
      handle_fork_if_needed

      size = @buffer.push(entry)
      return flush! if shutdown_requested?

      ensure_thread!
      drop_oldest_events if size > max_buffer_size
      request_flush if size >= RailsEventViewer.buffer_size
    end

    def flush!
      events = @buffer.drain([@buffer.size, max_buffer_size].min)
      return true if events.empty?

      written = @writer.write(events)
      report_dropped_events if written
      written
    rescue => e
      log_error("[RailsEventViewer] Failed to flush: #{e.message}")
      false
    end

    def stop!
      @mutex.synchronize { @shutdown_requested = true }

      if @thread&.alive?
        @flush_requests << true
        @thread.join(SHUTDOWN_TIMEOUT_SECONDS)
      end

      @mutex.synchronize { @thread = nil }

      loop do
        remaining = @buffer.size
        break if remaining.zero?

        flush!
        break if @buffer.size >= remaining
      end
    end

    def running?
      @thread&.alive? || false
    end

    def size
      @buffer.size
    end

    private

    def handle_fork_if_needed
      @mutex.synchronize do
        if @pid != Process.pid
          @pid = Process.pid
          @buffer.after_fork
          @writer.reset
          @flush_requests = Queue.new
          @thread = nil
          @shutdown_requested = false
          @dropped_count = 0
        end
      end
    end

    def max_buffer_size
      RailsEventViewer.buffer_size * MAX_BUFFER_MULTIPLIER
    end

    def drop_oldest_events
      while @buffer.size > max_buffer_size
        dropped = @buffer.drain(1)
        break if dropped.empty?

        @buffer.dead(dropped)
        @writer.forget(dropped)
        @mutex.synchronize { @dropped_count += 1 }
      end
    end

    def report_dropped_events
      dropped = @mutex.synchronize { @dropped_count.tap { @dropped_count = 0 } }
      return if dropped.zero?

      effective_logger&.warn("[RailsEventViewer] Dropped #{dropped} events because the buffer was full")
    end

    def request_flush
      @flush_requests << true if @flush_requests.empty? && @writer.failed_attempts.zero?
    end

    def ensure_thread!
      @mutex.synchronize do
        return if @thread&.alive?
        return if @shutdown_requested

        @thread = Thread.new { run_loop }
      end
    end

    def run_loop
      effective_logger&.debug("[RailsEventViewer] Flusher thread started (PID: #{Process.pid})")

      until shutdown_requested?
        begin
          wait_for_flush
          loop do
            break unless flush!
            break if @buffer.size < RailsEventViewer.buffer_size || shutdown_requested?
          end
        rescue => e
          log_error("[RailsEventViewer] Flusher error: #{e.message}")
        end
      end

      effective_logger&.debug("[RailsEventViewer] Flusher thread stopped (PID: #{Process.pid})")
    end

    def wait_for_flush
      backoff = 2**[@writer.failed_attempts, BatchWriter::MAX_ATTEMPTS].min
      @flush_requests.clear unless @writer.failed_attempts.zero?
      return if shutdown_requested?

      @flush_requests.pop(timeout: RailsEventViewer.flush_interval * backoff)
    end

    def shutdown_requested?
      @mutex.synchronize { @shutdown_requested }
    end
  end
end
