module RailsEventViewer
  class EventTypesController < ApplicationController
    def index
      @event_types = current_adapter.event_type_statistics
    end

    def show
      @event_type_name = params[:name]
      total_events = RailsEventViewer.events.with_name(@event_type_name)

      @pagy, @events = pagy_events(total_events)
      @total_count = @pagy.count
      @events_today = total_events.since(Time.current.beginning_of_day).count
    end
  end
end
