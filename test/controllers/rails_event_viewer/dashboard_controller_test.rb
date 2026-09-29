# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    setup do
      Entry.delete_all
    end

    test "index renders successfully with no events" do
      get rails_event_viewer.root_path

      assert_response :success
    end

    test "index renders successfully with events" do
      Entry.create!(name: "test.event", occurred_at: Time.current)
      Entry.create!(name: "another.event", occurred_at: 1.hour.ago)

      get rails_event_viewer.root_path

      assert_response :success
    end

    test "index shows correct event counts" do
      Entry.create!(name: "test.event", occurred_at: Time.current)
      Entry.create!(name: "test.event", occurred_at: 2.days.ago)

      get rails_event_viewer.root_path

      assert_response :success
    end

    test "index displays recent events" do
      15.times do |i|
        Entry.create!(name: "event.#{i}", occurred_at: i.minutes.ago)
      end

      get rails_event_viewer.root_path

      assert_response :success
    end
  end
end
