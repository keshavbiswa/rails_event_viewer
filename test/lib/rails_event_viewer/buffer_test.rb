require "test_helper"

module RailsEventViewer
  class BufferTest < ActiveSupport::TestCase
    class RecordingBuffer
      include RailsEventViewer::Buffer

      attr_reader :committed, :reverted, :forked

      def initialize
        @entries = []
        @committed = []
        @reverted = []
        @forked = false
      end

      def push(entry)
        @entries << entry
        @entries.size
      end

      def drain(limit)
        @entries.shift(limit)
      end

      def commit(entries)
        @committed.concat(entries)
      end

      def revert(entries)
        @reverted.concat(entries)
        @entries.unshift(*entries)
      end

      def size
        @entries.size
      end

      def after_fork
        @forked = true
      end
    end

    setup do
      Entry.delete_all
      @original_raise_on_error = Rails.event.instance_variable_get(:@raise_on_error)
    end

    teardown do
      Rails.event.raise_on_error = @original_raise_on_error
    end

    test "the memory buffer drains up to the limit and never blocks when empty" do
      buffer = Buffers::Memory.new
      3.times { |i| buffer.push({ name: "event.#{i}" }) }

      assert_equal 2, buffer.drain(2).size
      assert_equal 1, buffer.size
      assert_equal 1, buffer.drain(5).size
      assert_equal [], Timeout.timeout(1) { buffer.drain(5) }
    end

    test "the memory buffer returns its new size from push" do
      buffer = Buffers::Memory.new

      assert_equal 1, buffer.push({ name: "first" })
      assert_equal 2, buffer.push({ name: "second" })
    end

    test "the memory buffer starts empty again after a fork" do
      buffer = Buffers::Memory.new
      buffer.push({ name: "parent.event" })

      buffer.after_fork

      assert_equal 0, buffer.size
    end

    test "a configured buffer receives async events" do
      RailsEventViewer.async = true
      RailsEventViewer.buffer = RecordingBuffer.new
      subscriber = Subscriber.new
      subscriber.instance_variable_get(:@flusher).define_singleton_method(:ensure_thread!) { }

      subscriber.emit(event_hash("order.placed"))

      assert_equal 1, RailsEventViewer.buffer.size
    ensure
      subscriber&.stop!
    end

    test "a batch is committed only after it is written" do
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      subscriber = Subscriber.new
      buffer.push({ name: "order.placed", occurred_at: Time.current })
      entries_at_commit = []
      buffer.define_singleton_method(:commit) do |entries|
        entries_at_commit << Entry.count
        super(entries)
      end

      subscriber.flush!

      assert_equal ["order.placed"], buffer.committed.map { |e| e[:name] }
      assert_equal [1], entries_at_commit
    end

    test "a failed write is reverted into the buffer instead of committed" do
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_| raise ActiveRecord::StatementInvalid, "disk full" }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      buffer.push({ name: "order.placed", occurred_at: Time.current })

      assert_not subscriber.flush!

      assert_empty buffer.committed
      assert_equal ["order.placed"], buffer.reverted.map { |e| e[:name] }
      assert_equal 1, buffer.size
    end

    test "after three failed attempts, a batch is written one event at a time and the rejected event is kept" do
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      written = []
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |events|
        raise ActiveRecord::StatementInvalid, "bad payload" if events.any? { |e| e[:name] == "poison" }

        written.concat(events)
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      %w[good.1 poison good.2].each { |name| buffer.push({ name: name, occurred_at: Time.current }) }

      assert_not subscriber.flush!
      assert_not subscriber.flush!
      assert subscriber.flush!

      assert_equal %w[good.1 good.2], written.map { |e| e[:name] }
      assert_equal %w[good.1 good.2], buffer.committed.map { |e| e[:name] }
      assert_equal 1, buffer.size

      buffer.push({ name: "good.3", occurred_at: Time.current })
      assert subscriber.flush!, "with a rejected event still waiting, the next failure splits right away"
      assert_equal %w[good.1 good.2 good.3], buffer.committed.map { |e| e[:name] }
      assert_equal %w[poison], buffer.drain(5).map { |e| e[:name] }
    end

    test "an event is dropped only after it is rejected on its own three times" do
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |events|
        raise ActiveRecord::StatementInvalid, "bad payload" if events.any? { |e| e[:name] == "poison" }
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      buffer.push({ name: "poison", occurred_at: Time.current })

      3.times do |round|
        buffer.push({ name: "good.#{round}", occurred_at: Time.current })
        3.times { subscriber.flush! }
        assert_not_includes buffer.committed.map { |e| e[:name] }, "poison" if round < 2
      end

      assert_includes buffer.committed.map { |e| e[:name] }, "poison"
      assert_equal 0, buffer.size
    end

    test "a given-up event goes to the dead hook, logged with the error but not the payload" do
      buffer = RecordingBuffer.new
      given_up = []
      buffer.define_singleton_method(:dead) { |entries| given_up.concat(entries) }
      RailsEventViewer.buffer = buffer
      original_logger = RailsEventViewer.logger
      output = StringIO.new
      RailsEventViewer.logger = Logger.new(output)
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |events|
        raise ActiveRecord::StatementInvalid, "bad payload" if events.any? { |e| e[:name] == "poison" }
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      buffer.push({ name: "poison", payload: { order_id: 42 }, occurred_at: Time.current })

      3.times do |round|
        buffer.push({ name: "good.#{round}", occurred_at: Time.current })
        3.times { subscriber.flush! }
      end

      assert_equal %w[poison], given_up.map { |e| e[:name] }
      assert_not_includes buffer.committed.map { |e| e[:name] }, "poison"
      assert_match(/Gave up on 1 events the adapter rejected 3 times \(bad payload\): poison/, output.string)
      assert_no_match(/order_id/, output.string)
    ensure
      RailsEventViewer.logger = original_logger
    end

    test "giving up on many large events logs one bounded line" do
      original_logger = RailsEventViewer.logger
      output = StringIO.new
      RailsEventViewer.logger = Logger.new(output)
      buffer = RecordingBuffer.new
      events = Array.new(1000) { |i| { name: "event.#{i}", payload: { blob: "x" * 100_000 } } }

      BatchWriter.new(buffer).send(:give_up, events)

      assert_equal 1, output.string.lines.size
      assert_operator output.string.bytesize, :<, 1_000
      assert_match(/Gave up on 1000 events/, output.string)
      assert_equal 1000, buffer.committed.size
    ensure
      RailsEventViewer.logger = original_logger
    end

    test "events dropped by the buffer cap go to the dead hook" do
      original_buffer_size = RailsEventViewer.buffer_size
      RailsEventViewer.buffer_size = 1
      buffer = RecordingBuffer.new
      given_up = []
      buffer.define_singleton_method(:dead) { |entries| given_up.concat(entries) }
      flusher = Flusher.new(buffer)
      flusher.define_singleton_method(:ensure_thread!) { }

      12.times { |i| flusher.push({ name: "event.#{i}" }) }

      assert_equal %w[event.0 event.1], given_up.map { |e| e[:name] }
      assert_empty buffer.committed
    ensure
      RailsEventViewer.buffer_size = original_buffer_size
    end

    test "an event that fails once on its own is retried, not dropped" do
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      calls = Hash.new(0)
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |events|
        raise ActiveRecord::StatementInvalid, "batch failed" if events.size > 1

        name = events.first[:name]
        calls[name] += 1
        raise ActiveRecord::Deadlocked, "deadlock" if name == "unlucky" && calls[name] == 1
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      %w[good unlucky].each { |name| buffer.push({ name: name, occurred_at: Time.current }) }

      3.times { subscriber.flush! }

      assert_equal %w[good], buffer.committed.map { |e| e[:name] }
      assert subscriber.flush!
      assert_equal %w[good unlucky], buffer.committed.map { |e| e[:name] }
    end

    test "during an outage the split gives up after three failed writes and keeps the batch" do
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      calls = 0
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |_|
        calls += 1
        raise ActiveRecord::ConnectionNotEstablished, "database down"
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      10.times { |i| buffer.push({ name: "event.#{i}", occurred_at: Time.current }) }

      3.times { assert_not subscriber.flush! }

      assert_equal 1 + 1 + (1 + 3), calls
      assert_empty buffer.committed
      assert_equal 10, buffer.size
    end

    test "a capacity drop forgets the strikes of the events it drops" do
      original_buffer_size = RailsEventViewer.buffer_size
      RailsEventViewer.buffer_size = 1
      flusher = Flusher.new(RecordingBuffer.new)
      flusher.define_singleton_method(:ensure_thread!) { }
      strikes = flusher.instance_variable_get(:@writer).instance_variable_get(:@strikes)
      poison = { name: "poison" }
      strikes[poison] = 2

      flusher.push(poison)
      10.times { |i| flusher.push({ name: "event.#{i}" }) }

      assert_empty strikes
    ensure
      RailsEventViewer.buffer_size = original_buffer_size
    end

    test "the flusher backs off exponentially while writes keep failing, even as new events arrive" do
      RailsEventViewer.async = true
      original_buffer_size = RailsEventViewer.buffer_size
      original_flush_interval = RailsEventViewer.flush_interval
      RailsEventViewer.buffer_size = 1
      RailsEventViewer.flush_interval = 0.3
      RailsEventViewer.buffer = RecordingBuffer.new
      attempts = 0
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |_|
        attempts += 1
        raise ActiveRecord::StatementInvalid, "disk full"
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new

      25.times do |i|
        subscriber.emit(event_hash("order.#{i}"))
        sleep 0.02
      end

      assert_includes 1..2, attempts
    ensure
      subscriber&.stop!
      RailsEventViewer.buffer_size = original_buffer_size
      RailsEventViewer.flush_interval = original_flush_interval
    end

    test "the memory buffer keeps a reverted batch for the next flush" do
      buffer = Buffers::Memory.new
      buffer.push({ name: "order.placed" })

      buffer.revert(buffer.drain(1))

      assert_equal ["order.placed"], buffer.drain(1).map { |e| e[:name] }
    end

    test "the flusher waits for the next interval after a failed write instead of retrying at once" do
      RailsEventViewer.async = true
      original_buffer_size = RailsEventViewer.buffer_size
      original_flush_interval = RailsEventViewer.flush_interval
      RailsEventViewer.buffer_size = 1
      RailsEventViewer.flush_interval = 5
      RailsEventViewer.buffer = RecordingBuffer.new
      attempts = 0
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |_|
        attempts += 1
        raise ActiveRecord::StatementInvalid, "disk full"
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new

      subscriber.emit(event_hash("order.placed"))
      Timeout.timeout(2) { sleep 0.01 until attempts >= 1 }
      sleep 0.2

      assert_equal 1, attempts
    ensure
      subscriber&.stop!
      RailsEventViewer.buffer_size = original_buffer_size
      RailsEventViewer.flush_interval = original_flush_interval
    end

    test "a flush commits only the bounded batch it wrote" do
      original_buffer_size = RailsEventViewer.buffer_size
      RailsEventViewer.buffer_size = 2
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      subscriber = Subscriber.new
      30.times { |i| buffer.push({ name: "event.#{i}", occurred_at: Time.current }) }

      subscriber.flush!

      assert_equal 20, buffer.committed.size
      assert_equal 10, buffer.size
    ensure
      RailsEventViewer.buffer_size = original_buffer_size
    end

    test "events dropped from an overfull buffer are committed" do
      RailsEventViewer.async = true
      original_buffer_size = RailsEventViewer.buffer_size
      RailsEventViewer.buffer_size = 2
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      subscriber = Subscriber.new
      subscriber.instance_variable_get(:@flusher).define_singleton_method(:ensure_thread!) { }

      25.times { |i| subscriber.emit(event_hash("event.#{i}")) }

      assert_equal %w[event.0 event.1 event.2 event.3 event.4], buffer.committed.map { |e| e[:name] }
      assert_equal 20, buffer.size
    ensure
      RailsEventViewer.buffer_size = original_buffer_size
    end

    test "shutdown gives up instead of looping when a buffer cannot make progress" do
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_| raise ActiveRecord::StatementInvalid, "disk full" }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      subscriber = Subscriber.new
      buffer.push({ name: "order.placed", occurred_at: Time.current })

      Timeout.timeout(2) { subscriber.stop! }

      assert_equal 1, buffer.size
    end

    test "a forked child tells the buffer it forked" do
      skip "fork is not available" unless Process.respond_to?(:fork)

      RailsEventViewer.async = true
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      subscriber = Subscriber.new

      reader, writer = IO.pipe
      pid = fork do
        reader.close
        subscriber.emit(event_hash("child.event"))
        writer.write(buffer.forked.to_s)
        writer.close
      ensure
        exit!(0)
      end
      writer.close
      forked = reader.read
      Process.wait(pid)

      assert_equal "true", forked
    ensure
      subscriber&.stop!
    end

    test "a failed sync write is logged and reported to Rails instead of swallowed" do
      Rails.event.raise_on_error = false
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_| raise ActiveRecord::StatementInvalid, "disk full" }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)

      assert_error_reported(ActiveRecord::StatementInvalid) do
        Rails.event.notify("order.placed", id: 1)
      end
    end

    test "with raise_on_error, a failed sync write aborts the caller's transaction" do
      Rails.event.raise_on_error = true
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_| raise ActiveRecord::StatementInvalid, "disk full" }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)

      assert_raises(ActiveRecord::StatementInvalid) do
        Entry.transaction(requires_new: true) do
          Entry.create!(name: "business.change", occurred_at: Time.current)
          Rails.event.notify("order.placed", id: 1)
        end
      end

      assert_not Entry.exists?(name: "business.change")
    end

    test "a sync event rolls back with the caller's transaction" do
      Entry.transaction(requires_new: true) do
        Rails.event.notify("order.placed", id: 1)
        assert_equal 1, Entry.count
        raise ActiveRecord::Rollback
      end

      assert_equal 0, Entry.count
    end

    test "a forked child that never emits does not write the parent's buffered events on shutdown" do
      skip "fork is not available" unless Process.respond_to?(:fork)

      written_by_child = in_forked_child_of_a_buffering_parent do |flusher|
        flusher.stop!
        flusher.send(:shutdown_requested?)
      end

      assert_equal "", written_by_child
    end

    test "a forked child that never emits does not write the parent's buffered events on flush" do
      skip "fork is not available" unless Process.respond_to?(:fork)

      written_by_child = in_forked_child_of_a_buffering_parent do |flusher|
        flusher.flush!
      end

      assert_equal "", written_by_child
    end

    test "a buffered event keeps its payload, tags and context as they were at emit time" do
      RailsEventViewer.async = true
      RailsEventViewer.buffer = buffer = RecordingBuffer.new
      subscriber = Subscriber.new
      subscriber.instance_variable_get(:@flusher).define_singleton_method(:ensure_thread!) { }
      reporter = ActiveSupport::EventReporter.new(subscriber)
      items = { count: 1 }
      meta = { source: "web" }
      user = { id: 1 }

      reporter.set_context(user: user)
      reporter.tagged(meta: meta) { reporter.notify("order.created", items: items) }
      items[:count] = 2
      meta[:source] = "api"
      user[:id] = 2

      entry = buffer.drain(1).first
      assert_equal({ "items" => { "count" => 1 } }, entry[:payload])
      assert_equal({ "meta" => { "source" => "web" } }, entry[:tags])
      assert_equal({ "user" => { "id" => 1 } }, entry[:context])
    ensure
      reporter&.clear_context
      subscriber&.stop!
    end

    test "the flusher writes inside the Rails executor" do
      executor_active = nil
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_| executor_active = Rails.application.executor.active? }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      flusher = Flusher.new(RecordingBuffer.new)
      flusher.define_singleton_method(:ensure_thread!) { }
      flusher.push({ name: "order.created" })

      Thread.new { flusher.flush! }.join

      assert_equal true, executor_active
    end

    test "a failing executor hook leaves the events in the buffer" do
      buffer = RecordingBuffer.new
      flusher = Flusher.new(buffer)
      flusher.define_singleton_method(:ensure_thread!) { }
      flusher.push({ name: "order.created" })

      executor = Rails.application.executor
      executor.define_singleton_method(:run!) { |**| raise "hook failed" }

      flushed = Thread.new { flusher.flush! }.value

      assert_equal false, flushed
      assert_equal 1, buffer.size
    ensure
      executor&.singleton_class&.remove_method(:run!)
    end

    test "shutdown stops draining at its deadline and logs what was left" do
      original_buffer_size = RailsEventViewer.buffer_size
      original_logger = RailsEventViewer.logger
      RailsEventViewer.buffer_size = 1
      output = StringIO.new
      RailsEventViewer.logger = Logger.new(output)
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_| sleep 0.1 }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      buffer = RecordingBuffer.new
      100.times { |i| buffer.push({ name: "event.#{i}" }) }
      flusher = Flusher.new(buffer)
      flusher.define_singleton_method(:shutdown_timeout) { 0.25 }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      flusher.stop!
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :<, 0.6
      assert_operator buffer.size, :>, 0
      assert_equal 100, buffer.committed.size + buffer.size
      assert_includes output.string, "[RailsEventViewer] #{buffer.size} events still buffered at shutdown"
    ensure
      RailsEventViewer.buffer_size = original_buffer_size
      RailsEventViewer.logger = original_logger
    end

    test "a clean shutdown writes everything and logs no leftovers" do
      original_logger = RailsEventViewer.logger
      output = StringIO.new
      RailsEventViewer.logger = Logger.new(output)
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |_| }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      buffer = RecordingBuffer.new
      5.times { |i| buffer.push({ name: "event.#{i}" }) }

      Flusher.new(buffer).stop!

      assert_equal 0, buffer.size
      assert_no_match(/still buffered at shutdown/, output.string)
    ensure
      RailsEventViewer.logger = original_logger
    end

    test "shutdown does not split a failing batch into single writes" do
      calls = 0
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |events|
        calls += 1
        raise ActiveRecord::StatementInvalid, "flaky" if events.size > 1 || calls > 2
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      buffer = RecordingBuffer.new
      10.times { |i| buffer.push({ name: "event.#{i}" }) }
      flusher = Flusher.new(buffer)
      flusher.instance_variable_get(:@writer).instance_variable_set(:@failed_attempts, BatchWriter::MAX_ATTEMPTS - 1)

      flusher.stop!

      assert_equal 1, calls
      assert_equal 10, buffer.size
    end

    test "shutdown warns when the flusher thread is still busy" do
      original_logger = RailsEventViewer.logger
      output = StringIO.new
      RailsEventViewer.logger = Logger.new(output)
      RailsEventViewer.async = true
      writing = Queue.new
      adapter = Object.new
      adapter.define_singleton_method(:write_events) do |_|
        writing << true
        sleep 0.3
      end
      RailsEventViewer.instance_variable_set(:@adapter, adapter)
      original_buffer_size = RailsEventViewer.buffer_size
      RailsEventViewer.buffer_size = 1
      flusher = Flusher.new(RecordingBuffer.new)
      flusher.define_singleton_method(:shutdown_timeout) { 0.05 }
      flusher.push({ name: "event.0" })
      Timeout.timeout(2) { writing.pop }
      thread = flusher.instance_variable_get(:@thread)

      flusher.stop!

      assert_includes output.string, "[RailsEventViewer] Flusher thread still busy after 0.05s"
    ensure
      thread&.join(2)
      RailsEventViewer.buffer_size = original_buffer_size
      RailsEventViewer.logger = original_logger
    end

    private

    def in_forked_child_of_a_buffering_parent
      flusher = Flusher.new(Buffers::Memory.new)
      flusher.define_singleton_method(:ensure_thread!) { }
      flusher.push({ name: "parent.event", occurred_at: Time.current })

      reader, writer = IO.pipe
      adapter = Object.new
      adapter.define_singleton_method(:write_events) { |events| writer.write(events.map { |e| e[:name] }.join(",")) }
      RailsEventViewer.instance_variable_set(:@adapter, adapter)

      pid = fork do
        reader.close
        succeeded = yield(flusher)
        writer.close
        exit!(succeeded ? 0 : 1)
      rescue Exception
        exit!(1)
      end
      writer.close
      written = reader.read
      reader.close
      Process.wait(pid)

      assert Process.last_status.success?, "the forked child failed"
      written
    end

    def event_hash(name)
      { name: name, payload: {}, timestamp: (Time.current.to_f * 1_000_000_000).to_i }
    end
  end
end
