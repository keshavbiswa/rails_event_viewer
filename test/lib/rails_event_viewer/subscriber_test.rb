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

    test "tracks PID for fork detection" do
      assert_equal Process.pid, @subscriber.instance_variable_get(:@pid)
    end

    test "buffer_size returns current buffer size" do
      # In sync mode, buffer stays empty
      assert_equal 0, @subscriber.buffer_size
    end
  end
end
