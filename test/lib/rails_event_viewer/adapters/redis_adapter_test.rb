# frozen_string_literal: true

require "test_helper"
require "mock_redis"
require "rails_event_viewer/adapters/redis"

module RailsEventViewer
  module Adapters
    class RedisAdapterTest < ActiveSupport::TestCase
      setup do
        @redis = MockRedis.new
        pool = ConnectionPool.new(size: 1) { @redis }
        @adapter = RailsEventViewer::Adapters::Redis.new(pool: pool)
      end

      teardown do
        @adapter.clear!
      end

      test "write_events stores events" do
        write_event("user.created")

        assert_equal 1, @redis.zcard("{rails_event_viewer}:events")
      end

      test "write_events stores multiple events" do
        write_event("user.created")
        write_event("order.placed")

        assert_equal 2, @redis.zcard("{rails_event_viewer}:events")
      end

      test "write_events stores event names" do
        write_event("user.created")
        write_event("order.placed")

        assert_includes @adapter.distinct_event_names, "user.created"
        assert_includes @adapter.distinct_event_names, "order.placed"
      end

      test "find_event returns event by id" do
        write_event("user.created")
        relation = EventsRelation.new(adapter: @adapter)
        event = @adapter.fetch_events(relation).first

        found = @adapter.find_event(event[:id])
        assert_not_nil found
        assert_equal "user.created", found[:name]
      end

      test "find_event returns nil for unknown id" do
        assert_nil @adapter.find_event("9999999999999999-deadbeef")
      end

      test "find_event returns nil for invalid id format" do
        assert_nil @adapter.find_event("not-a-valid-id")
      end

      test "find_event works for timestamps that would fail float round-trip" do
        # This specific timestamp has microseconds that get truncated during
        # float multiplication — the original bug. Use a fixed time to reproduce it.
        occurred_at = Time.at(1750329825.123457)
        write_event("student.updated", occurred_at: occurred_at)

        relation = EventsRelation.new(adapter: @adapter)
        event = @adapter.fetch_events(relation).first

        found = @adapter.find_event(event[:id])
        assert_not_nil found, "find_event failed for a timestamp with float precision loss"
        assert_equal "student.updated", found[:name]
      end

      test "find_event works when two events share the same microsecond timestamp" do
        occurred_at = Time.at(1750329825.123456)

        write_event("student.created", occurred_at: occurred_at)
        write_event("student.updated", occurred_at: occurred_at)

        relation = EventsRelation.new(adapter: @adapter)
        events = @adapter.fetch_events(relation)

        events.each do |event|
          found = @adapter.find_event(event[:id])
          assert_not_nil found, "find_event failed for #{event[:name]}"
          assert_equal event[:name], found[:name]
          assert_equal event[:id], found[:id]
        end
      end

      test "fetch_events returns events in reverse chronological order" do
        write_event("old", occurred_at: 2.hours.ago)
        write_event("new", occurred_at: 1.hour.ago)

        relation = EventsRelation.new(adapter: @adapter)
        results = @adapter.fetch_events(relation)

        assert_equal "new", results.first[:name]
        assert_equal "old", results.last[:name]
      end

      test "fetch_events filters by name" do
        write_event("user.created")
        write_event("order.placed")

        relation = EventsRelation.new(adapter: @adapter).with_name("user.created")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "user.created", results.first[:name]
      end

      test "fetch_events filters by tag" do
        write_event("event1", tags: { env: "prod" })
        write_event("event2", tags: { env: "dev" })

        relation = EventsRelation.new(adapter: @adapter).with_tag(:env, "prod")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "event1", results.first[:name]
      end

      test "fetch_events filters by context when value is an integer but filter value is a string" do
        # Context values stored via JSON keep their original type (e.g. an
        # ActiveRecord id stays an Integer), but params from a URL are always
        # strings. The filter must match across that type difference.
        write_event("student.created", context: { student_id: 2 })
        write_event("student.created", context: { student_id: 3 })

        relation = EventsRelation.new(adapter: @adapter).with_context("student_id", "2")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal 2, results.first[:context][:student_id]
      end

      test "fetch_events filters by time range" do
        write_event("old", occurred_at: 2.days.ago)
        write_event("new", occurred_at: 1.hour.ago)

        relation = EventsRelation.new(adapter: @adapter).since(1.day.ago)
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "new", results.first[:name]
      end

      test "count_events returns total when unfiltered" do
        write_event("user.created")
        write_event("order.placed")

        relation = EventsRelation.new(adapter: @adapter)
        assert_equal 2, @adapter.count_events(relation)
      end

      test "count_events respects filters" do
        write_event("user.created")
        write_event("order.placed")

        relation = EventsRelation.new(adapter: @adapter).with_name("user.created")
        assert_equal 1, @adapter.count_events(relation)
      end

      test "distinct_event_names returns sorted unique names" do
        write_event("user.created")
        write_event("user.created")
        write_event("order.placed")

        names = @adapter.distinct_event_names
        assert_equal ["order.placed", "user.created"], names
      end

      test "events keep their microseconds, and delete_before leaves an event at the exact cutoff" do
        cutoff = Time.at(1_700_000_000, 123_456, :usec)
        write_event("at.cutoff", occurred_at: cutoff)

        assert_equal 0, @adapter.delete_before(cutoff)

        stored = @adapter.fetch_events(EventsRelation.new(adapter: @adapter)).first
        assert_equal cutoff, stored[:occurred_at]
      end

      test "delete_before removes old events" do
        write_event("old", occurred_at: 2.days.ago)
        write_event("new", occurred_at: 1.hour.ago)

        @adapter.delete_before(1.day.ago)

        relation = EventsRelation.new(adapter: @adapter)
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "new", results.first[:name]
      end

      test "count_since returns events after timestamp" do
        write_event("old", occurred_at: 2.days.ago)
        write_event("new", occurred_at: 1.hour.ago)

        assert_equal 1, @adapter.count_since(1.day.ago)
      end

      test "clear! removes all events" do
        write_event("user.created")
        @adapter.clear!

        relation = EventsRelation.new(adapter: @adapter)
        assert_equal 0, @adapter.count_events(relation)
      end

      test "fetch_events filters before paginating" do
        30.times { |i| write_event("order.placed", occurred_at: (i + 10).minutes.ago) }
        5.times { |i| write_event("user.created", occurred_at: i.minutes.ago) }

        relation = EventsRelation.new(adapter: @adapter).with_name("order.placed").limit(25)

        assert_equal 25, @adapter.fetch_events(relation).size
        assert_equal 5, @adapter.fetch_events(relation.offset(25)).size
      end

      test "distinct_event_names drops names whose events were deleted" do
        write_event("old.event", occurred_at: 2.days.ago)
        write_event("user.created")

        @adapter.delete_before(1.day.ago)

        assert_equal ["user.created"], @adapter.distinct_event_names
      end

      test "distinct_event_names drops names whose events were trimmed" do
        pool = ConnectionPool.new(size: 1) { @redis }
        adapter = RailsEventViewer::Adapters::Redis.new(pool: pool, max_events: 1)
        adapter.write_events([{ name: "old.event", occurred_at: 1.minute.ago }])
        adapter.write_events([{ name: "user.created", occurred_at: Time.current }])

        assert_equal ["user.created"], adapter.distinct_event_names
      end

      test "distinct_event_names keeps a name when an older event arrives late" do
        write_event("user.created", occurred_at: Time.current)
        write_event("user.created", occurred_at: 2.days.ago)

        @adapter.delete_before(1.day.ago)

        assert_equal ["user.created"], @adapter.distinct_event_names
      end

      test "write_events leaves no temporary name keys behind" do
        write_event("user.created")

        assert_equal ["{rails_event_viewer}:events", "{rails_event_viewer}:name_index"], @redis.keys("*").sort
      end

      test "every key shares one Redis Cluster hash tag" do
        write_event("user.created")
        @adapter.delete_before(1.day.from_now)
        write_event("order.placed")

        assert @redis.keys("*").all? { |key| key.start_with?("{rails_event_viewer}:") }
      end

      test "last on a filtered relation returns the oldest match across pages" do
        30.times { |i| write_event("order.placed", occurred_at: i.minutes.ago) }
        write_event("user.created", occurred_at: 2.hours.ago)

        relation = EventsRelation.new(adapter: @adapter).with_name("order.placed")

        assert_equal "order.placed", relation.last[:name]
        assert_in_delta 29.minutes.ago.to_f, relation.last[:occurred_at].to_f, 1.0
      end

      private

      def write_event(name, occurred_at: Time.current, tags: {}, context: {}, payload: {})
        @adapter.write_events([{
          name: name,
          payload: payload,
          tags: tags,
          context: context,
          occurred_at: occurred_at
        }])
      end
    end
  end
end
