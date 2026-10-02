module RailsEventViewer
  class EventTypesController < ApplicationController
    def index
      @event_types = current_adapter.event_type_statistics
    end

    def show
      @event_type_name = string_param(:name)
      return redirect_to event_types_path unless @event_type_name

      total_events = RailsEventViewer.events.with_name(@event_type_name)

      @pagination, @events = paginate(total_events)
      @total_count = @pagination.count
      @events_today = total_events.since(Time.current.beginning_of_day).count
    end
  end
end
