require "test_helper"

module RailsEventViewer
  class EventsRelationTest < ActiveSupport::TestCase
    setup do
      @relation = EventsRelation.new
      Entry.delete_all
    end

    test "last returns the oldest event across all pages" do
      30.times { |i| Entry.create!(name: "event.#{i}", occurred_at: i.minutes.ago) }

      assert_equal "event.29", @relation.last.name
    end

    test "last returns nil when empty" do
      assert_nil @relation.last
    end

    test "with_name filters by single name" do
      Entry.create!(name: "user.created", occurred_at: Time.current)
      Entry.create!(name: "order.placed", occurred_at: Time.current)

      results = @relation.with_name("user.created").to_a
      assert_equal 1, results.size
      assert_equal "user.created", results.first.name
    end

    test "with_name filters by multiple names" do
      Entry.create!(name: "user.created", occurred_at: Time.current)
      Entry.create!(name: "order.placed", occurred_at: Time.current)
      Entry.create!(name: "payment.processed", occurred_at: Time.current)

      results = @relation.with_name("user.created", "order.placed").to_a
      assert_equal 2, results.size
    end

    test "with_tag filters by tag key and value" do
      Entry.create!(name: "event1", tags: { "env" => "production" }, occurred_at: Time.current)
      Entry.create!(name: "event2", tags: { "env" => "development" }, occurred_at: Time.current)

      results = @relation.with_tag(:env, "production").to_a
      assert_equal 1, results.size
      assert_equal "event1", results.first.name
    end

    test "search filters by name or payload" do
      Entry.create!(name: "user.created", payload: { "email" => "test@example.com" }, occurred_at: Time.current)
      Entry.create!(name: "order.placed", payload: { "item" => "widget" }, occurred_at: Time.current)

      results = @relation.search("user").to_a
      assert_equal 1, results.size
      assert_equal "user.created", results.first.name
    end

    test "since filters by time" do
      old_event = Entry.create!(name: "old", occurred_at: 2.days.ago)
      new_event = Entry.create!(name: "new", occurred_at: 1.hour.ago)

      results = @relation.since(1.day.ago).to_a
      assert_equal 1, results.size
      assert_equal "new", results.first.name
    end

    test "until filters by time" do
      old_event = Entry.create!(name: "old", occurred_at: 2.days.ago)
      new_event = Entry.create!(name: "new", occurred_at: 1.hour.ago)

      results = @relation.until(1.day.ago).to_a
      assert_equal 1, results.size
      assert_equal "old", results.first.name
    end

    test "limit restricts results" do
      5.times { |i| Entry.create!(name: "event#{i}", occurred_at: Time.current) }

      results = @relation.limit(3).to_a
      assert_equal 3, results.size
    end

    test "offset skips results" do
      5.times { |i| Entry.create!(name: "event#{i}", occurred_at: Time.current - i.seconds) }

      results = @relation.offset(2).limit(10).to_a
      assert_equal 3, results.size
    end

    test "count returns total count" do
      3.times { Entry.create!(name: "test", occurred_at: Time.current) }

      assert_equal 3, @relation.count
    end

    test "count respects filters" do
      Entry.create!(name: "user.created", occurred_at: Time.current)
      Entry.create!(name: "order.placed", occurred_at: Time.current)

      assert_equal 1, @relation.with_name("user.created").count
    end

    test "first returns single event" do
      Entry.create!(name: "first", occurred_at: 1.hour.ago)
      Entry.create!(name: "second", occurred_at: Time.current)

      result = @relation.first
      assert_equal "second", result.name
      assert_equal %w[first], @relation.with_name(:first).to_a.map(&:name)
    end

    test "any? returns true when events exist" do
      Entry.create!(name: "test", occurred_at: Time.current)
      assert @relation.any?
    end

    test "any? returns false when no events" do
      refute @relation.any?
    end

    test "empty? returns true when no events" do
      assert @relation.empty?
    end

    test "each iterates over events" do
      3.times { Entry.create!(name: "test", occurred_at: Time.current) }

      names = []
      @relation.each { |e| names << e.name }
      assert_equal 3, names.size
    end

    test "filtered? returns true when filters applied" do
      refute @relation.filtered?
      assert @relation.with_name("test").filtered?
      assert @relation.with_tag(:env, "prod").filtered?
      assert @relation.search("query").filtered?
      assert @relation.since(1.hour.ago).filtered?
    end

    test "chaining methods returns new relation" do
      rel1 = @relation.with_name("test")
      rel2 = rel1.since(1.hour.ago)

      refute_same rel1, rel2
      assert_equal ["test"], rel1.names
      assert_equal ["test"], rel2.names
      assert_nil rel1.since_time
      refute_nil rel2.since_time
    end
  end
end
