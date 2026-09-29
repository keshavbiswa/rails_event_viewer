require "test_helper"
require "rails_event_viewer/adapters/memory"

module RailsEventViewer
  module Adapters
    class MemoryAdapterTest < ActiveSupport::TestCase
      setup do
        @adapter = RailsEventViewer::Adapters::Memory.new(max_events: 100)
        @adapter.clear!
      end

      test "write_events stores events" do
        events = [
          { name: "test.event", payload: { key: "value" }, occurred_at: Time.current }
        ]

        @adapter.write_events(events)
        assert_equal 1, @adapter.size
      end

      test "write_events assigns sequential IDs" do
        events = [
          { name: "event1", occurred_at: Time.current },
          { name: "event2", occurred_at: Time.current }
        ]

        @adapter.write_events(events)

        stored = @adapter.events.to_a
        assert_equal 1, stored[0][:id]
        assert_equal 2, stored[1][:id]
      end

      test "fetch_events returns events in reverse chronological order" do
        events = [
          { name: "old", occurred_at: 2.hours.ago },
          { name: "new", occurred_at: 1.hour.ago }
        ]

        @adapter.write_events(events)

        relation = EventsRelation.new(adapter: @adapter)
        results = @adapter.fetch_events(relation)

        assert_equal "new", results.first[:name]
        assert_equal "old", results.last[:name]
      end

      test "fetch_events respects limit and offset" do
        5.times { |i| @adapter.write_events([{ name: "event#{i}", occurred_at: Time.current - i.seconds }]) }

        relation = EventsRelation.new(adapter: @adapter).limit(2).offset(1)
        results = @adapter.fetch_events(relation)

        assert_equal 2, results.size
      end

      test "fetch_events filters by name" do
        @adapter.write_events([
          { name: "user.created", occurred_at: Time.current },
          { name: "order.placed", occurred_at: Time.current }
        ])

        relation = EventsRelation.new(adapter: @adapter).with_name("user.created")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "user.created", results.first[:name]
      end

      test "fetch_events filters by tags" do
        @adapter.write_events([
          { name: "event1", tags: { "env" => "prod" }, occurred_at: Time.current },
          { name: "event2", tags: { "env" => "dev" }, occurred_at: Time.current }
        ])

        relation = EventsRelation.new(adapter: @adapter).with_tag("env", "prod")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "event1", results.first[:name]
      end

      test "fetch_events filters by time range" do
        @adapter.write_events([
          { name: "old", occurred_at: 2.days.ago },
          { name: "new", occurred_at: 1.hour.ago }
        ])

        relation = EventsRelation.new(adapter: @adapter).since(1.day.ago)
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "new", results.first[:name]
      end

      test "fetch_events filters by search query" do
        @adapter.write_events([
          { name: "user.created", payload: { "email" => "test@example.com" }, occurred_at: Time.current },
          { name: "order.placed", payload: { "item" => "widget" }, occurred_at: Time.current }
        ])

        relation = EventsRelation.new(adapter: @adapter).search("user")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "user.created", results.first[:name]
      end

      test "count_events returns total count" do
        3.times { @adapter.write_events([{ name: "test", occurred_at: Time.current }]) }

        relation = EventsRelation.new(adapter: @adapter)
        assert_equal 3, @adapter.count_events(relation)
      end

      test "count_events respects filters" do
        @adapter.write_events([
          { name: "user.created", occurred_at: Time.current },
          { name: "order.placed", occurred_at: Time.current }
        ])

        relation = EventsRelation.new(adapter: @adapter).with_name("user.created")
        assert_equal 1, @adapter.count_events(relation)
      end

      test "distinct_event_names returns unique names" do
        @adapter.write_events([
          { name: "user.created", occurred_at: Time.current },
          { name: "user.created", occurred_at: Time.current },
          { name: "order.placed", occurred_at: Time.current }
        ])

        names = @adapter.distinct_event_names
        assert_equal ["order.placed", "user.created"], names
      end

      test "find_event returns event by id" do
        @adapter.write_events([{ name: "test", occurred_at: Time.current }])

        event = @adapter.find_event(1)
        assert_equal "test", event[:name]
      end

      test "find_event returns nil for missing id" do
        assert_nil @adapter.find_event(999)
      end

      test "delete_before removes old events" do
        @adapter.write_events([
          { name: "old", occurred_at: 2.days.ago },
          { name: "new", occurred_at: 1.hour.ago }
        ])

        deleted = @adapter.delete_before(1.day.ago)
        assert_equal 1, deleted
        assert_equal 1, @adapter.size
      end

      test "events_over_time groups by interval" do
        @adapter.write_events([
          { name: "event1", occurred_at: 1.hour.ago },
          { name: "event2", occurred_at: 1.hour.ago + 1.minute },
          { name: "event3", occurred_at: 30.minutes.ago }
        ])

        result = @adapter.events_over_time(since: 2.hours.ago, interval: :hour)
        assert_instance_of Hash, result
      end

      test "counts_by_name returns event counts" do
        @adapter.write_events([
          { name: "user.created", occurred_at: Time.current },
          { name: "user.created", occurred_at: Time.current },
          { name: "order.placed", occurred_at: Time.current }
        ])

        result = @adapter.counts_by_name(limit: 10)
        assert_equal 2, result["user.created"]
        assert_equal 1, result["order.placed"]
      end

      test "count_since returns events after timestamp" do
        @adapter.write_events([
          { name: "old", occurred_at: 2.days.ago },
          { name: "new", occurred_at: 1.hour.ago }
        ])

        assert_equal 1, @adapter.count_since(1.day.ago)
      end

      test "trims to max_events" do
        adapter = RailsEventViewer::Adapters::Memory.new(max_events: 3)

        5.times { |i| adapter.write_events([{ name: "event#{i}", occurred_at: Time.current }]) }

        assert_equal 3, adapter.size
      end

      test "clear! removes all events" do
        @adapter.write_events([{ name: "test", occurred_at: Time.current }])
        @adapter.clear!

        assert_equal 0, @adapter.size
      end

      test "supports_retention? returns true" do
        assert @adapter.supports_retention?
      end

      test "fetch_events filters by tags with symbol keys" do
        @adapter.write_events([
          { name: "event1", tags: { env: "prod" }, occurred_at: Time.current },
          { name: "event2", tags: { env: "dev" }, occurred_at: Time.current }
        ])

        relation = EventsRelation.new(adapter: @adapter).with_tag(:env, "prod")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "event1", results.first[:name]
      end

      test "fetch_events filters by tag presence (nil value)" do
        @adapter.write_events([
          { name: "event1", tags: { env: "prod" }, occurred_at: Time.current },
          { name: "event2", tags: {}, occurred_at: Time.current }
        ])

        relation = EventsRelation.new(adapter: @adapter).with_tag("env", nil)
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "event1", results.first[:name]
      end

      test "fetch_events searches in payload" do
        @adapter.write_events([
          { name: "event1", payload: { email: "user@example.com" }, occurred_at: Time.current },
          { name: "event2", payload: { item: "widget" }, occurred_at: Time.current }
        ])

        relation = EventsRelation.new(adapter: @adapter).search("example.com")
        results = @adapter.fetch_events(relation)

        assert_equal 1, results.size
        assert_equal "event1", results.first[:name]
      end

      test "trimming drops the oldest events by time, not by arrival order" do
        adapter = RailsEventViewer::Adapters::Memory.new(max_events: 2)
        adapter.write_events([{ name: "new", occurred_at: Time.current }])
        adapter.write_events([{ name: "late.old", occurred_at: 1.day.ago }])
        adapter.write_events([{ name: "newer", occurred_at: 1.second.from_now }])

        assert_equal ["new", "newer"], adapter.distinct_event_names
      end
    end
  end
end
