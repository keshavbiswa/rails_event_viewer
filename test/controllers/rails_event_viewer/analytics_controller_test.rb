# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class AnalyticsControllerTest < ActionDispatch::IntegrationTest
    setup do
      Entry.delete_all
      Entry.create!(name: "test.event", occurred_at: Time.current)
    end

    test "overview with valid date range" do
      get rails_event_viewer.analytics_overview_path(
        start_date: 7.days.ago.to_date.to_s,
        end_date: Date.current.to_s
      )
      assert_response :success
    end

    test "overview with invalid start_date falls back to default" do
      get rails_event_viewer.analytics_overview_path(
        start_date: "not-a-date",
        end_date: Date.current.to_s
      )
      assert_response :success
    end

    test "overview with invalid end_date falls back to default" do
      get rails_event_viewer.analytics_overview_path(
        start_date: 7.days.ago.to_date.to_s,
        end_date: "invalid"
      )
      assert_response :success
    end

    test "overview with both dates invalid falls back to defaults" do
      get rails_event_viewer.analytics_overview_path(
        start_date: "foo",
        end_date: "bar"
      )
      assert_response :success
    end

    test "overview with start_date after end_date swaps them" do
      get rails_event_viewer.analytics_overview_path(
        start_date: Date.current.to_s,
        end_date: 7.days.ago.to_date.to_s
      )
      assert_response :success
    end

    test "overview without date params uses defaults" do
      get rails_event_viewer.analytics_overview_path
      assert_response :success
    end

    test "overview counts only events inside the selected range" do
      original = RailsEventViewer.storage_adapter

      [:active_record, :memory].each do |storage|
        RailsEventViewer.storage_adapter = storage
        RailsEventViewer.reset_adapter!
        Entry.delete_all
        RailsEventViewer.adapter.clear! if storage == :memory
        old = Array.new(11) { { name: "old.event", occurred_at: 30.days.ago } }
        RailsEventViewer.adapter.write_events(old + [{ name: "new.event", occurred_at: Time.current }])

        get rails_event_viewer.analytics_overview_path

        assert_equal [1, 1, { "new.event" => 1 }, 1], overview_numbers, storage

        get rails_event_viewer.analytics_overview_path(start_date: 40.days.ago.to_date.to_s, end_date: 20.days.ago.to_date.to_s)

        assert_equal [11, 1, { "old.event" => 11 }, 11], overview_numbers, storage
      end
    ensure
      RailsEventViewer.adapter.clear! if RailsEventViewer.storage_adapter == :memory
      RailsEventViewer.storage_adapter = original
      RailsEventViewer.reset_adapter!
    end

    private

    def overview_numbers
      total, types, by_type, over_time = %i[@total_events @unique_event_types @events_by_type @events_over_time].map do |name|
        controller.instance_variable_get(name)
      end
      [total, types, by_type, over_time.values.sum]
    end
  end
end
