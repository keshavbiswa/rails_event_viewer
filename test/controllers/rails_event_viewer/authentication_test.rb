# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class AuthenticationTest < ActionDispatch::IntegrationTest
    teardown do
      Rails.env = "test"
      RailsEventViewer.authentication = nil
      RailsEventViewer.http_basic_auth_enabled = false
      RailsEventViewer.http_basic_auth_user = nil
      RailsEventViewer.http_basic_auth_password = nil
    end

    test "dashboard is open outside production when no auth is configured" do
      get rails_event_viewer.root_path

      assert_response :success
    end

    test "dashboard is forbidden in production when no auth is configured" do
      Rails.env = "production"

      get rails_event_viewer.root_path

      assert_response :forbidden
    end

    test "dashboard is forbidden in staging when no auth is configured" do
      Rails.env = "staging"

      get rails_event_viewer.root_path

      assert_response :forbidden
    end

    test "basic auth with blank configured credentials rejects blank submitted credentials" do
      RailsEventViewer.http_basic_auth_enabled = true

      get rails_event_viewer.root_path, headers: basic_auth("", "")

      assert_response :forbidden
    end

    test "basic auth accepts the configured credentials" do
      enable_basic_auth

      get rails_event_viewer.root_path, headers: basic_auth("admin", "secret")

      assert_response :success
    end

    test "basic auth rejects a wrong user, a wrong password, or no credentials" do
      enable_basic_auth

      [basic_auth("admin", "wrong"), basic_auth("wrong", "secret"), {}].each do |headers|
        get rails_event_viewer.root_path, headers: headers

        assert_response :unauthorized
      end
    end

    test "basic auth with a user but no password is forbidden" do
      RailsEventViewer.http_basic_auth_enabled = true
      RailsEventViewer.http_basic_auth_user = "admin"

      get rails_event_viewer.root_path, headers: basic_auth("admin", "")

      assert_response :forbidden
    end

    test "custom authentication returning false or nil is unauthorized" do
      [false, nil].each do |result|
        RailsEventViewer.authentication = ->(_controller) { result }

        get rails_event_viewer.root_path

        assert_response :unauthorized
      end
    end

    test "custom authentication that redirects keeps the redirect" do
      RailsEventViewer.authentication = ->(controller) { controller.redirect_to("/login") && nil }

      get rails_event_viewer.root_path

      assert_redirected_to "/login"
    end

    test "custom authentication still applies in production" do
      Rails.env = "production"
      RailsEventViewer.authentication = ->(_controller) { true }

      get rails_event_viewer.root_path

      assert_response :success
    end

    private

    def enable_basic_auth
      RailsEventViewer.http_basic_auth_enabled = true
      RailsEventViewer.http_basic_auth_user = "admin"
      RailsEventViewer.http_basic_auth_password = "secret"
    end

    def basic_auth(user, password)
      { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
    end
  end
end
