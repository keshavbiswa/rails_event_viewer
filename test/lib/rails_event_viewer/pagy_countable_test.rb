# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class PagyCountableTest < ActiveSupport::TestCase
    setup do
      Entry.delete_all

      10.times do |i|
        Entry.create!(
          name: "event.#{i}",
          occurred_at: i.minutes.ago
        )
      end

      @relation = RailsEventViewer.events
      @countable = PagyCountable.new(@relation)
    end

    test "#count returns total number of events" do
      assert_equal 10, @countable.count
    end

    test "#count with argument still works" do
      assert_equal 10, @countable.count(:all)
    end

    test "#offset returns OffsetWrapper" do
      result = @countable.offset(5)

      assert_kind_of PagyCountable::OffsetWrapper, result
    end

    test "#offset then limit returns array of records" do
      result = @countable.offset(0).limit(5)

      assert_kind_of Array, result
      assert_equal 5, result.size
    end

    test "#offset skips correct number of records" do
      first_page = @countable.offset(0).limit(3)
      second_page = @countable.offset(3).limit(3)

      first_page_names = first_page.map(&:name)
      second_page_names = second_page.map(&:name)

      assert_empty first_page_names & second_page_names
    end

    test "#offset wrapper to_a returns all remaining records" do
      result = @countable.offset(7).to_a

      assert_kind_of Array, result
      assert_equal 3, result.size
    end

    test "works with filtered relation" do
      Entry.create!(name: "special.event", occurred_at: Time.current)

      filtered = RailsEventViewer.events.with_name("special.event")
      countable = PagyCountable.new(filtered)

      assert_equal 1, countable.count
      assert_equal 1, countable.offset(0).limit(10).size
    end

    test "works with empty relation" do
      Entry.delete_all

      countable = PagyCountable.new(RailsEventViewer.events)

      assert_equal 0, countable.count
      assert_empty countable.offset(0).limit(10)
    end

    test "#limit respects requested count" do
      result = @countable.offset(0).limit(3)
      assert_equal 3, result.size

      result = @countable.offset(0).limit(1)
      assert_equal 1, result.size
    end

    test "#offset beyond count returns empty array" do
      result = @countable.offset(100).limit(10)
      assert_empty result
    end

    test "integrates with Pagy pagination" do
      # Simulate what Pagy does internally
      items = 25
      page = 1
      count = @countable.count

      offset = (page - 1) * items
      records = @countable.offset(offset).limit(items)

      assert_equal 10, count
      assert_equal 10, records.size
    end

    test "works with second page" do
      items = 3
      page = 2

      offset = (page - 1) * items
      records = @countable.offset(offset).limit(items)

      assert_equal 3, records.size
    end
  end
end
