module RailsEventViewer
  class EventsController < ApplicationController
    def index
      relation = apply_filters(RailsEventViewer.events)
      @pagination, @events = paginate(relation)
      @event_names = current_adapter.distinct_event_names
    end

    def show
      @event = current_adapter.find_event(params[:id])

      if @event.nil?
        redirect_to events_path, alert: "Event not found"
        return
      end

      @related_events = find_related_events(@event)
    end

    def search
      @query = params[:q]
      relation = RailsEventViewer.events.search(@query)
      @pagination, @events = paginate(relation)
      @event_names = current_adapter.distinct_event_names

      render :index
    end

    private

    def apply_filters(relation)
      relation = relation.with_name(params[:name]) if params[:name].present?

      @start_date = safe_parse_date(params[:start_date])
      @end_date = safe_parse_date(params[:end_date])
      relation = relation.since(@start_date.beginning_of_day) if @start_date
      relation = relation.until(@end_date.end_of_day) if @end_date

      if params[:tag_key].present?
        relation = relation.with_tag(params[:tag_key], params[:tag_value].presence)
      end

      if params[:context_key].present?
        relation = relation.with_context(params[:context_key], params[:context_value].presence)
      end

      if params[:q].present?
        relation = relation.search(params[:q])
      end

      relation
    end

    def find_related_events(event)
      context = event.respond_to?(:context) ? event.context : event[:context]
      return [] unless context.present?

      # Find events with matching request_id in context
      request_id = context["request_id"] || context[:request_id]
      return [] unless request_id

      event_id = event.respond_to?(:id) ? event.id : event[:id]

      RailsEventViewer.events
        .with_context("request_id", request_id)
        .limit(11)
        .to_a
        .reject { |e| (e.respond_to?(:id) ? e.id : e[:id]) == event_id }
        .first(10)
    end
  end
end
