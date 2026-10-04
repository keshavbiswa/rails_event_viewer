module RailsEventViewer
  class DashboardController < ApplicationController
    def index
      @total_events = RailsEventViewer.events.count
      @events_today = current_adapter.count_since(Time.current.beginning_of_day)
      @event_names = current_adapter.distinct_event_names
      @recent_events = RailsEventViewer.events.limit(10).to_a

      if analytics_supported?
        @events_by_type = current_adapter.counts_by_name(limit: 10)
        @events_over_time = current_adapter.events_over_time(range: 24.hours.ago.beginning_of_hour.., interval: :hour)
      else
        @events_by_type = {}
        @events_over_time = {}
      end
    end
  end
end
