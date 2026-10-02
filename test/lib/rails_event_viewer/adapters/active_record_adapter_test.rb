# frozen_string_literal: true

require "test_helper"
require "rails_event_viewer/adapters/active_record"

module RailsEventViewer
  module Adapters
    class ActiveRecordAdapterTest < ActiveSupport::TestCase
      setup do
        @adapter = RailsEventViewer::Adapters::ActiveRecord.new
        Entry.delete_all
      end

      test "table_exists? returns true when table exists" do
        assert @adapter.table_exists?
      end

      test "write_events creates entries" do
        events = [
          {
            name: "test.event",
            payload: { key: "value" },
            tags: { env: "test" },
            context: { request_id: "123" },
            source_file: "/test.rb",
            source_line: 42,
            source_label: "test_method",
            occurred_at: Time.current
          }
        ]

        assert_difference -> { Entry.count }, 1 do
          @adapter.write_events(events)
        end

        entry = Entry.last
        assert_equal "test.event", entry.name
        assert_equal({ "key" => "value" }, entry.payload)
        assert_equal({ "env" => "test" }, entry.tags)
        assert_equal({ "request_id" => "123" }, entry.context)
        assert_equal "/test.rb", entry.source_file
        assert_equal 42, entry.source_line
        assert_equal "test_method", entry.source_label
      end

      test "write_events handles empty array" do
        assert_no_difference -> { Entry.count } do
          @adapter.write_events([])
        end
      end

      test "fetch_events returns entries ordered by occurred_at desc" do
        Entry.create!(name: "old", occurred_at: 2.hours.ago)
        Entry.create!(name: "new", occurred_at: 1.hour.ago)

        relation = EventsRelation.new(adapter: @adapter)
        results = @adapter.fetch_events(relation).to_a

        assert_equal "new", results.first.name
        assert_equal "old", results.last.name
      end

      test "fetch_events applies limit and offset" do
        5.times { |i| Entry.create!(name: "event#{i}", occurred_at: Time.current - i.seconds) }

        relation = EventsRelation.new(adapter: @adapter).limit(2).offset(1)
        results = @adapter.fetch_events(relation).to_a

        assert_equal 2, results.size
      end

      test "fetch_events filters by name" do
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "order.placed", occurred_at: Time.current)

        relation = EventsRelation.new(adapter: @adapter).with_name("user.created")
        results = @adapter.fetch_events(relation).to_a

        assert_equal 1, results.size
        assert_equal "user.created", results.first.name
      end

      test "fetch_events filters by multiple names" do
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "order.placed", occurred_at: Time.current)
        Entry.create!(name: "payment.processed", occurred_at: Time.current)

        relation = EventsRelation.new(adapter: @adapter).with_name("user.created", "order.placed")
        results = @adapter.fetch_events(relation).to_a

        assert_equal 2, results.size
      end

      test "fetch_events filters by time range" do
        Entry.create!(name: "old", occurred_at: 2.days.ago)
        Entry.create!(name: "new", occurred_at: 1.hour.ago)

        relation = EventsRelation.new(adapter: @adapter).since(1.day.ago)
        results = @adapter.fetch_events(relation).to_a

        assert_equal 1, results.size
        assert_equal "new", results.first.name
      end

      test "fetch_events filters by search query on name" do
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "order.placed", occurred_at: Time.current)

        relation = EventsRelation.new(adapter: @adapter).search("user")
        results = @adapter.fetch_events(relation).to_a

        assert_equal 1, results.size
        assert_equal "user.created", results.first.name
      end

      test "count_events returns total count" do
        3.times { Entry.create!(name: "test", occurred_at: Time.current) }

        relation = EventsRelation.new(adapter: @adapter)
        assert_equal 3, @adapter.count_events(relation)
      end

      test "count_events respects filters" do
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "order.placed", occurred_at: Time.current)

        relation = EventsRelation.new(adapter: @adapter).with_name("user.created")
        assert_equal 1, @adapter.count_events(relation)
      end

      test "distinct_event_names returns sorted unique names" do
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "order.placed", occurred_at: Time.current)

        names = @adapter.distinct_event_names
        assert_equal ["order.placed", "user.created"], names
      end

      test "find_event returns entry by id" do
        entry = Entry.create!(name: "test", occurred_at: Time.current)

        found = @adapter.find_event(entry.id)
        assert_equal entry.id, found.id
      end

      test "find_event returns nil for missing id" do
        assert_nil @adapter.find_event(99999)
      end

      test "delete_before removes old entries" do
        Entry.create!(name: "old", occurred_at: 2.days.ago)
        Entry.create!(name: "new", occurred_at: 1.hour.ago)

        deleted = @adapter.delete_before(1.day.ago)
        assert_equal 1, deleted
        assert_equal 1, Entry.count
      end

      test "events_over_time groups by hour" do
        Entry.create!(name: "event1", occurred_at: 1.hour.ago)
        Entry.create!(name: "event2", occurred_at: 30.minutes.ago)

        result = @adapter.events_over_time(since: 2.hours.ago, interval: :hour)
        assert_instance_of Hash, result
      end

      test "counts_by_name returns name counts" do
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "user.created", occurred_at: Time.current)
        Entry.create!(name: "order.placed", occurred_at: Time.current)

        result = @adapter.counts_by_name(limit: 10)
        assert_equal 2, result["user.created"]
        assert_equal 1, result["order.placed"]
      end

      test "counts_by_name respects limit" do
        Entry.create!(name: "a", occurred_at: Time.current)
        Entry.create!(name: "b", occurred_at: Time.current)
        Entry.create!(name: "c", occurred_at: Time.current)

        result = @adapter.counts_by_name(limit: 2)
        assert_equal 2, result.size
      end

      test "count_since returns count after timestamp" do
        Entry.create!(name: "old", occurred_at: 2.days.ago)
        Entry.create!(name: "new", occurred_at: 1.hour.ago)

        assert_equal 1, @adapter.count_since(1.day.ago)
      end

      test "event_type_statistics returns stats for all event types" do
        Entry.create!(name: "user.created", occurred_at: 2.hours.ago)
        Entry.create!(name: "user.created", occurred_at: 1.hour.ago)
        Entry.create!(name: "order.placed", occurred_at: 30.minutes.ago)

        stats = @adapter.event_type_statistics

        assert_equal 2, stats.size

        user_stats = stats.find { |s| s[:name] == "user.created" }
        order_stats = stats.find { |s| s[:name] == "order.placed" }

        assert_equal 2, user_stats[:count]
        assert_equal 1, order_stats[:count]
        assert_not_nil user_stats[:last_event_at]
        assert_not_nil order_stats[:last_event_at]
      end

      test "event_type_statistics orders by count descending" do
        3.times { Entry.create!(name: "popular", occurred_at: Time.current) }
        Entry.create!(name: "unpopular", occurred_at: Time.current)

        stats = @adapter.event_type_statistics

        assert_equal "popular", stats.first[:name]
        assert_equal "unpopular", stats.last[:name]
      end

      test "event_type_statistics returns empty array when no events" do
        stats = @adapter.event_type_statistics
        assert_equal [], stats
      end

      test "distinct_group_values returns unique context values for a key" do
        Entry.create!(name: "test", context: { "request_id" => "req-1" }, occurred_at: Time.current)
        Entry.create!(name: "test", context: { "request_id" => "req-1" }, occurred_at: Time.current)
        Entry.create!(name: "test", context: { "request_id" => "req-2" }, occurred_at: Time.current)

        values = @adapter.distinct_group_values("request_id", source: :context)

        assert_includes values, "req-1"
        assert_includes values, "req-2"
        assert_equal 2, values.size
      end

      test "distinct_group_values returns unique tag values for a key" do
        Entry.create!(name: "test", tags: { "env" => "production" }, occurred_at: Time.current)
        Entry.create!(name: "test", tags: { "env" => "production" }, occurred_at: Time.current)
        Entry.create!(name: "test", tags: { "env" => "staging" }, occurred_at: Time.current)

        values = @adapter.distinct_group_values("env", source: :tags)

        assert_includes values, "production"
        assert_includes values, "staging"
        assert_equal 2, values.size
      end

      test "group_instances returns stats grouped by context key" do
        travel_to Time.zone.local(2026, 1, 1, 12, 0, 0) do
          3.times { Entry.create!(name: "test", context: { "request_id" => "req-1" }, occurred_at: Time.current) }
          2.times { Entry.create!(name: "test", context: { "request_id" => "req-2" }, occurred_at: Time.current) }
        end

        instances = @adapter.group_instances("request_id", source: :context)

        assert_equal 2, instances.size

        req1 = instances.find { |i| i[:value] == "req-1" }
        req2 = instances.find { |i| i[:value] == "req-2" }

        assert_equal 3, req1[:count]
        assert_equal 2, req2[:count]
        assert_not_nil req1[:first_event_at]
        assert_not_nil req1[:last_event_at]
      end

      test "group_instances respects limit" do
        3.times { |i| Entry.create!(name: "test", context: { "request_id" => "req-#{i}" }, occurred_at: Time.current) }

        instances = @adapter.group_instances("request_id", source: :context, limit: 2)

        assert_equal 2, instances.size
      end

      test "group_instances merges a number with its string form and skips blank and null values" do
        Entry.create!(name: "a", context: { "user_id" => 42 }, occurred_at: Time.current)
        Entry.create!(name: "b", context: { "user_id" => "42" }, occurred_at: Time.current)
        Entry.create!(name: "c", context: { "user_id" => "" }, occurred_at: Time.current)
        Entry.create!(name: "d", context: { "user_id" => nil }, occurred_at: Time.current)

        instances = @adapter.group_instances("user_id", source: :context)

        assert_equal [["42", 2]], instances.map { |instance| [instance[:value], instance[:count]] }
      end

      test "group_instances works for a key with a hyphen" do
        Entry.create!(name: "a", context: { "trace-id" => "t1" }, occurred_at: Time.current)

        instances = @adapter.group_instances("trace-id", source: :context)

        assert_equal [["t1", 1]], instances.map { |instance| [instance[:value], instance[:count]] }
      end

      test "event_time_span returns min and max occurred_at for filtered events" do
        Entry.create!(name: "test", context: { "request_id" => "req-1" }, occurred_at: 2.hours.ago)
        Entry.create!(name: "test", context: { "request_id" => "req-1" }, occurred_at: 30.minutes.ago)
        Entry.create!(name: "other", context: { "request_id" => "req-2" }, occurred_at: Time.current)

        relation = EventsRelation.new(adapter: @adapter).with_context("request_id", "req-1")
        first_at, last_at = @adapter.event_time_span(relation)

        assert_not_nil first_at
        assert_not_nil last_at
        assert first_at < last_at
        assert_in_delta 90 * 60, (last_at - first_at), 5.0
      end

      test "event_time_span returns nils when no events match" do
        relation = EventsRelation.new(adapter: @adapter).with_name("nonexistent")
        first_at, last_at = @adapter.event_time_span(relation)

        assert_nil first_at
        assert_nil last_at
      end

      test "timestamps from aggregate queries are read as UTC regardless of server zone" do
        original_tz = ENV["TZ"]
        ENV["TZ"] = "Asia/Kolkata"
        occurred_at = Time.utc(2026, 1, 1, 12, 0, 0)
        Entry.create!(name: "tz.check", occurred_at: occurred_at)

        stats = @adapter.event_type_statistics.find { |s| s[:name] == "tz.check" }
        span = @adapter.event_time_span(EventsRelation.new(adapter: @adapter).with_name("tz.check"))

        assert_equal occurred_at, stats[:last_event_at]
        assert_equal [occurred_at, occurred_at], span
      ensure
        ENV["TZ"] = original_tz
      end

      test "search is case-insensitive on name and payload" do
        Entry.create!(name: "user.created", payload: { email: "Alice@Example.com" }, occurred_at: Time.current)

        relation = EventsRelation.new(adapter: @adapter)

        assert_equal 1, @adapter.fetch_events(relation.search("USER.CREATED")).to_a.size
        assert_equal 1, @adapter.fetch_events(relation.search("alice@example")).to_a.size
      end

      test "search matches percent, underscore and exclamation mark literally" do
        Entry.create!(name: "sale.started", payload: { note: "50% off_now!" }, occurred_at: Time.current)
        Entry.create!(name: "sale.ended", payload: { note: "500 offXnow" }, occurred_at: Time.current)

        relation = EventsRelation.new(adapter: @adapter)

        assert_equal ["sale.started"], @adapter.fetch_events(relation.search("50%")).map(&:name)
        assert_equal ["sale.started"], @adapter.fetch_events(relation.search("off_now")).map(&:name)
        assert_equal ["sale.started"], @adapter.fetch_events(relation.search("now!")).map(&:name)
      end

      test "fetch_last returns the oldest matching event" do
        Entry.create!(name: "a", occurred_at: 1.minute.ago)
        oldest = Entry.create!(name: "a", occurred_at: 1.day.ago)
        Entry.create!(name: "b", occurred_at: 2.days.ago)

        assert_equal oldest, EventsRelation.new(adapter: @adapter).with_name("a").last
      end
    end
  end
end
