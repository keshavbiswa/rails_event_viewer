# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class SelfHostedAssetsTest < ActionDispatch::IntegrationTest
    NONCE = "test-nonce"
    CSP_KEYS = %w[
      action_dispatch.content_security_policy
      action_dispatch.content_security_policy_nonce_generator
      action_dispatch.content_security_policy_nonce_directives
    ].freeze
    ASSETS = %w[
      rails_event_viewer/application-
      rails_event_viewer/chart.umd.min-
      rails_event_viewer/chartjs-adapter-date-fns.bundle.min-
      rails_event_viewer/chartkick.min-
    ].freeze

    setup do
      Entry.delete_all
      @event = Entry.create!(name: "order.placed", payload: { id: 1 }, context: { request_id: "r1" }, occurred_at: Time.current)

      @original_group_keys = RailsEventViewer.group_keys
      RailsEventViewer.group_keys = [:request_id]

      @original_csp = Rails.application.env_config.slice(*CSP_KEYS)
      Rails.application.env_config.merge!(
        "action_dispatch.content_security_policy" => ActionDispatch::ContentSecurityPolicy.new { |policy|
          policy.default_src :self
          policy.script_src :self
          policy.style_src :self
        },
        "action_dispatch.content_security_policy_nonce_generator" => ->(_request) { NONCE },
        "action_dispatch.content_security_policy_nonce_directives" => %w[script-src]
      )
    end

    teardown do
      Rails.application.env_config.merge!(@original_csp)
      RailsEventViewer.group_keys = @original_group_keys
    end

    test "every page works under a strict content security policy" do
      pages.each do |path|
        get path

        assert_response :success
        assert_equal [], external_assets, "#{path} loads assets from another origin"
        assert_equal [], css_select("script").reject { |tag| tag["nonce"] == NONCE }.map(&:to_html), "#{path} has a script without the nonce"
        assert_equal [], css_select("[style]").map(&:name), "#{path} has an inline style attribute"
        assert_equal [], inline_handlers, "#{path} has an inline event handler"
        assert_empty css_select("a[href^='javascript:']"), "#{path} has a javascript: link"
      end
    end

    test "clickable rows, copy button and progress bars use data attributes" do
      get rails_event_viewer.root_path
      assert_select "tr[data-event-viewer-href]"

      get rails_event_viewer.events_path
      assert_select "tr[data-event-viewer-href]"

      get rails_event_viewer.event_type_path("order.placed")
      assert_select "tr[data-event-viewer-href]"

      get rails_event_viewer.event_path(@event)
      assert_select "button[data-event-viewer-copy]"

      get rails_event_viewer.analytics_overview_path
      assert_select "[data-event-viewer-width]"
    end

    test "engine assets are linked and served" do
      get rails_event_viewer.root_path

      urls = css_select("script[src], link[rel=stylesheet]").map { |tag| tag["src"] || tag["href"] }
      ASSETS.each do |asset|
        assert urls.any? { |url| url.include?(asset) }, "#{asset} is not linked: #{urls.inspect}"
      end

      urls.each do |url|
        get url
        assert_response :success, url
      end
    end

    private

    def pages
      [
        rails_event_viewer.root_path,
        rails_event_viewer.events_path,
        rails_event_viewer.event_path(@event),
        rails_event_viewer.event_types_path,
        rails_event_viewer.event_type_path("order.placed"),
        rails_event_viewer.groups_path,
        rails_event_viewer.group_path("r1", key: "request_id"),
        rails_event_viewer.analytics_overview_path
      ]
    end

    def external_assets
      css_select("script[src], link[href], img[src], iframe[src]")
        .map { |tag| tag["src"] || tag["href"] }
        .reject { |url| url.start_with?("/") && !url.start_with?("//") }
    end

    def inline_handlers
      css_select("*").flat_map { |node| node.attribute_nodes.map(&:name) }.select { |name| name.start_with?("on") }
    end
  end
end
