require "test_helper"

module RailsEventViewer
  class SubscriberTest < ActiveSupport::TestCase
    setup do
      @subscriber = Subscriber.new
      RailsEventViewer.async = false
    end

    test "emit creates entry from hash" do
      event_hash = {
        name: "test.event",
        payload: { key: "value" },
        tags: { env: "test" },
        context: { request_id: "123" },
        timestamp: (Time.current.to_f * 1_000_000_000).to_i,
        source_location: { filepath: "/test.rb", lineno: 1, label: "test" }
      }

      assert_difference "Entry.count", 1 do
        @subscriber.emit(event_hash)
      end

      entry = Entry.last
      assert_equal "test.event", entry.name
      assert_equal({ "key" => "value" }, entry.payload)
      assert_equal({ "env" => "test" }, entry.tags)
      assert_equal({ "request_id" => "123" }, entry.context)
      assert_equal "/test.rb", entry.source_file
      assert_equal 1, entry.source_line
      assert_equal "test", entry.source_label
    end

    test "emit handles nil payload" do
      event_hash = {
        name: "test.event",
        payload: nil,
        timestamp: (Time.current.to_f * 1_000_000_000).to_i
      }

      assert_difference "Entry.count", 1 do
        @subscriber.emit(event_hash)
      end

      assert_equal({}, Entry.last.payload)
    end

    test "emit ignores events without name" do
      event_hash = {
        payload: { key: "value" },
        timestamp: Time.current.to_i * 1_000_000_000
      }

      assert_no_difference "Entry.count" do
        @subscriber.emit(event_hash)
      end
    end

    test "emit ignores non-hash events" do
      assert_no_difference "Entry.count" do
        @subscriber.emit("not a hash")
      end
    end

    test "respects ignored_events configuration" do
      RailsEventViewer.ignored_events = ["ignored.event"]

      event_hash = {
        name: "ignored.event",
        timestamp: (Time.current.to_f * 1_000_000_000).to_i
      }

      assert_no_difference "Entry.count" do
        @subscriber.emit(event_hash)
      end
    end

    test "respects captured_events configuration" do
      RailsEventViewer.captured_events = [/^user\./]

      user_event = {
        name: "user.created",
        timestamp: (Time.current.to_f * 1_000_000_000).to_i
      }

      order_event = {
        name: "order.placed",
        timestamp: (Time.current.to_f * 1_000_000_000).to_i
      }

      assert_difference "Entry.count", 1 do
        @subscriber.emit(user_event)
        @subscriber.emit(order_event)
      end

      assert_equal "user.created", Entry.last.name
    end

    test "buffer_size returns current buffer size" do
      # In sync mode, buffer stays empty
      @subscriber.emit(event_hash("sync.event"))

      assert_equal 0, @subscriber.buffer_size
      assert_not @subscriber.running?
    end

    test "flusher thread starts on the first buffered event, not at boot" do
      RailsEventViewer.async = true
      subscriber = Subscriber.new

      assert_not subscriber.running?

      subscriber.emit(event_hash("lazy.event"))

      assert subscriber.running?
      assert_difference "Entry.count", 1 do
        subscriber.stop!
      end
      assert_not subscriber.running?
    ensure
      subscriber&.stop!
    end

    test "ignored events do not start the flusher thread" do
      RailsEventViewer.async = true
      subscriber = Subscriber.new

      subscriber.emit(event_hash("active_record.sql"))

      assert_not subscriber.running?
      assert_equal 0, subscriber.buffer_size
    ensure
      subscriber&.stop!
    end

    test "events emitted after stop are written instead of lost" do
      RailsEventViewer.async = true
      subscriber = Subscriber.new
      subscriber.stop!

      assert_difference "Entry.count", 1 do
        subscriber.emit(event_hash("late.event"))
      end
      assert_not subscriber.running?
    end

    test "flusher lifecycle is logged at debug level only" do
      RailsEventViewer.async = true
      info_output = StringIO.new
      debug_output = StringIO.new
      original_logger = RailsEventViewer.logger

      subscribers = []
      [[info_output, :info], [debug_output, :debug]].each do |output, level|
        RailsEventViewer.logger = Logger.new(output, level: level)
        subscribers << Subscriber.new
        subscribers.last.emit(event_hash("quiet.event"))
        subscribers.last.stop!
      end

      assert_no_match(/Flusher thread/, info_output.string)
      assert_match(/Flusher thread started/, debug_output.string)
      assert_match(/Flusher thread stopped/, debug_output.string)
    ensure
      subscribers&.each(&:stop!)
      RailsEventViewer.logger = original_logger
    end

    test "a forked child starts its own flusher thread on its first event" do
      skip "fork is not available" unless Process.respond_to?(:fork)

      RailsEventViewer.async = true
      subscriber = Subscriber.new
      subscriber.emit(event_hash("parent.event"))

      reader, writer = IO.pipe
      pid = fork do
        reader.close
        subscriber.emit(event_hash("child.event"))
        writer.write(subscriber.running?.to_s)
        writer.close
        exit!(0)
      end
      writer.close
      child_running = reader.read
      Process.wait(pid)

      assert_equal "true", child_running
    ensure
      subscriber&.stop!
    end

    test "a full buffer is written by the flusher thread, not the emitting thread" do
      RailsEventViewer.async = true
      original_buffer_size = RailsEventViewer.buffer_size
      original_flush_interval = RailsEventViewer.flush_interval
      RailsEventViewer.buffer_size = 2
      RailsEventViewer.flush_interval = 60
      writers = Queue.new
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_events| writers << Thread.current }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)

      subscriber = Subscriber.new
      subscriber.emit(event_hash("full.1"))
      flusher = subscriber.instance_variable_get(:@flusher).instance_variable_get(:@thread)
      subscriber.emit(event_hash("full.2"))

      writer = Timeout.timeout(2) { writers.pop }
      assert_equal flusher, writer
      refute_equal Thread.current, writer
    ensure
      subscriber&.stop!
      RailsEventViewer.buffer_size = original_buffer_size
      RailsEventViewer.flush_interval = original_flush_interval
    end

    test "a burst is flushed right away instead of waiting for the interval" do
      RailsEventViewer.async = true
      original_buffer_size = RailsEventViewer.buffer_size
      original_flush_interval = RailsEventViewer.flush_interval
      RailsEventViewer.buffer_size = 100
      RailsEventViewer.flush_interval = 60
      written = Queue.new
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |events| events.each { |e| written << e } }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)

      subscriber = Subscriber.new
      150.times { |i| subscriber.emit(event_hash("burst.#{i}")) }

      Timeout.timeout(2) { sleep 0.01 until written.size >= 100 }
      assert_operator written.size, :>=, 100
    ensure
      subscriber&.stop!
      RailsEventViewer.buffer_size = original_buffer_size
      RailsEventViewer.flush_interval = original_flush_interval
    end

    test "an overfull buffer drops the oldest events and logs how many" do
      RailsEventViewer.async = true
      original_buffer_size = RailsEventViewer.buffer_size
      original_logger = RailsEventViewer.logger
      RailsEventViewer.buffer_size = 2
      output = StringIO.new
      RailsEventViewer.logger = Logger.new(output)
      written = []
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |events| written.concat(events) }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)

      subscriber = Subscriber.new
      subscriber.instance_variable_get(:@flusher).define_singleton_method(:ensure_thread!) { }
      25.times { |i| subscriber.emit(event_hash("event.#{i}")) }

      assert_equal 20, subscriber.buffer_size
      subscriber.stop!

      assert_equal 20, written.size
      assert_equal "event.5", written.first[:name]
      assert_match(/Dropped 5 events because the buffer was full/, output.string)
    ensure
      RailsEventViewer.buffer_size = original_buffer_size
      RailsEventViewer.logger = original_logger
    end

    test "a single flush is bounded by the buffer cap" do
      original_buffer_size = RailsEventViewer.buffer_size
      RailsEventViewer.buffer_size = 2
      written = []
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |events| written << events.size }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      buffer = RailsEventViewer.buffer
      30.times { |i| buffer.push({ name: "event.#{i}" }) }

      subscriber.flush!

      assert_equal [20], written
      assert_equal 10, subscriber.buffer_size
    ensure
      RailsEventViewer.buffer_size = original_buffer_size
    end

    private

    def event_hash(name)
      { name: name, payload: {}, timestamp: (Time.current.to_f * 1_000_000_000).to_i }
    end
  end
end
