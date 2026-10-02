module RailsEventViewer
  class AnalyticsController < ApplicationController
    before_action :check_analytics_support

    def overview
      @date_range = parse_date_range
      counts = current_adapter.counts_by_name(range: @date_range)

      @total_events = counts.values.sum
      @unique_event_types = counts.size
      @events_by_type = counts.first(20).to_h
      @events_over_time = current_adapter.events_over_time(range: @date_range, interval: period_for_range)

      @avg_events_per_hour = calculate_avg_events_per_hour
      @peak_period = find_peak_period
    end

    private

    def check_analytics_support
      unless analytics_supported?
        redirect_to root_path, alert: "Analytics not supported by current storage adapter"
      end
    end

    def parse_date_range
      start_date = safe_parse_date(params[:start_date], default: 7.days.ago.to_date)
      end_date = safe_parse_date(params[:end_date], default: Date.current)

      start_date, end_date = end_date, start_date if start_date > end_date

      start_date.beginning_of_day..end_date.end_of_day
    end

    def period_for_range
      duration = (@date_range.end - @date_range.begin).to_i
      duration <= 604800 ? :hour : :day
    end

    def calculate_avg_events_per_hour
      hours = ((@date_range.end - @date_range.begin) / 3600.0).round(1)
      return 0 if hours.zero?

      (@total_events.to_f / hours).round(1)
    end

    def find_peak_period
      return nil if @events_over_time.empty?

      @events_over_time.max_by { |_, count| count }
    end
  end
end
