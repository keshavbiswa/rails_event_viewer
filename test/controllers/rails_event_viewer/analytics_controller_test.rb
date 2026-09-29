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

    test "events_by_type clamps a negative limit" do
      original = RailsEventViewer.storage_adapter
      RailsEventViewer.storage_adapter = :memory
      RailsEventViewer.reset_adapter!

      get rails_event_viewer.analytics_events_by_type_path(limit: -1, format: :json)

      assert_response :success
    ensure
      RailsEventViewer.storage_adapter = original
      RailsEventViewer.reset_adapter!
    end
  end
end
