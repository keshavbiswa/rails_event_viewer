# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class TimeUtilsTest < ActiveSupport::TestCase
    test "truncate_to_interval returns nil for nil time" do
      assert_nil TimeUtils.truncate_to_interval(nil, :hour)
    end

    test "truncate_to_interval with :hour truncates to start of hour" do
      time = Time.new(2024, 6, 15, 14, 30, 45, "+00:00")
      result = TimeUtils.truncate_to_interval(time, :hour)

      assert_equal 2024, result.year
      assert_equal 6, result.month
      assert_equal 15, result.day
      assert_equal 14, result.hour
      assert_equal 0, result.min
      assert_equal 0, result.sec
    end

    test "truncate_to_interval with :day truncates to start of day" do
      time = Time.new(2024, 6, 15, 14, 30, 45, "+00:00")
      result = TimeUtils.truncate_to_interval(time, :day)

      assert_equal 2024, result.year
      assert_equal 6, result.month
      assert_equal 15, result.day
      assert_equal 0, result.hour
      assert_equal 0, result.min
      assert_equal 0, result.sec
    end

    test "truncate_to_interval preserves timezone offset" do
      time = Time.new(2024, 6, 15, 14, 30, 45, "+05:30")
      result = TimeUtils.truncate_to_interval(time, :hour)

      assert_equal time.utc_offset, result.utc_offset
    end
  end
end
