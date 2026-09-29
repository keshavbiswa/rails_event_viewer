# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class TimeZoneTest < ActionDispatch::IntegrationTest
    test "viewer time zone does not leak into the thread after the request" do
      Time.zone = "UTC"
      cookies[:timezone] = "Tokyo"

      get rails_event_viewer.root_path

      assert_response :success
      assert_equal "UTC", Time.zone.name
    end

    test "an unknown time zone cookie falls back to UTC" do
      cookies[:timezone] = "Not/AZone"

      get rails_event_viewer.root_path

      assert_response :success
    end
  end
end
