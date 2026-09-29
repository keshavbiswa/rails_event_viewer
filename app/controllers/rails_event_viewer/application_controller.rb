module RailsEventViewer
  class ApplicationController < ActionController::Base
    include Pagy::Method

    layout "rails_event_viewer/application"

    before_action :authenticate!
    around_action :use_viewer_time_zone

    helper_method :current_timezone, :current_adapter, :analytics_supported?, :persistence_supported?

    private

    def authenticate!
      if RailsEventViewer.http_basic_auth_enabled
        expected_user = RailsEventViewer.http_basic_auth_user.to_s
        expected_password = RailsEventViewer.http_basic_auth_password.to_s

        if expected_user.empty? || expected_password.empty?
          render plain: "RailsEventViewer: http_basic_auth_user and http_basic_auth_password must be set", status: :forbidden
          return
        end

        authenticate_or_request_with_http_basic do |user, password|
          ActiveSupport::SecurityUtils.secure_compare(user.to_s, expected_user) &
            ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)
        end
        return
      end

      auth = RailsEventViewer.authentication
      if auth.nil?
        return true if Rails.env.local?

        render plain: "RailsEventViewer: configure authentication or http_basic_auth", status: :forbidden
        return
      end

      render plain: "Unauthorized", status: :unauthorized unless auth.call(self) || performed?
    end

    def use_viewer_time_zone(&block)
      zone = ActiveSupport::TimeZone[cookies[:timezone].to_s] || ActiveSupport::TimeZone["UTC"]
      Time.use_zone(zone, &block)
    end

    def safe_parse_date(date_string, default: nil)
      return default if date_string.blank?

      Date.parse(date_string)
    rescue Date::Error, TypeError
      default
    end

    def current_timezone
      Time.zone.name
    end

    def current_adapter
      RailsEventViewer.adapter
    end

    def analytics_supported?
      current_adapter.supports_analytics?
    end

    def persistence_supported?
      current_adapter.supports_persistence?
    end

    def per_page
      (params[:per_page] || RailsEventViewer.per_page).to_i.clamp(1, 100)
    end

    # Helper to create paginated results from EventsRelation
    # Uses a countable wrapper to make EventsRelation work with Pagy
    def pagy_events(relation)
      countable = RailsEventViewer::PagyCountable.new(relation)
      pagy, records = pagy(:offset, countable, limit: per_page)

      [pagy, records.to_a]
    end
  end
end
