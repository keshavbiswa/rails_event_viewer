module RailsEventViewer
  class EventsController < ApplicationController
    def index
      relation = apply_filters(RailsEventViewer.events)
      @filtered = relation.filtered?
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

    private

    def apply_filters(relation)
      name = string_param(:name)
      tag_key = string_param(:tag_key)
      context_key = string_param(:context_key)
      @query = string_param(:q)

      @start_date = safe_parse_date(params[:start_date])
      @end_date = safe_parse_date(params[:end_date])

      relation = relation.with_name(name) if name
      relation = relation.since(@start_date.beginning_of_day) if @start_date
      relation = relation.until(@end_date.end_of_day) if @end_date
      relation = relation.with_tag(tag_key, string_param(:tag_value)) if tag_key
      relation = relation.with_context(context_key, string_param(:context_value)) if context_key
      relation = relation.search(@query) if @query
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
