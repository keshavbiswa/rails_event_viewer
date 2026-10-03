module RailsEventViewer
  class ApplicationController < ActionController::Base
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

    def string_param(key)
      value = params[key]
      value if value.is_a?(String) && !value.empty?
    end

    def safe_parse_date(date_string, default: nil)
      return default unless date_string.is_a?(String) && date_string.present?

      date = Date.parse(date_string)
      date.year.between?(1000, 9999) ? date : default
    rescue ArgumentError
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
      (string_param(:per_page) || RailsEventViewer.per_page).to_i.clamp(1, 100)
    end

    def paginate(relation)
      pagination = Page.new(count: relation.count, per_page: per_page, page: string_param(:page))
      [pagination, relation.offset(pagination.offset).limit(pagination.per_page).to_a]
    end
  end
end
