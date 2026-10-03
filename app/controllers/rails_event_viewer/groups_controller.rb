module RailsEventViewer
  class GroupsController < ApplicationController
    def index
      @group_keys = RailsEventViewer.group_keys
      @selected_key = params[:key].presence_in(@group_keys.map(&:to_s)) || @group_keys.first&.to_s
      @source = source_param

      if @selected_key.present?
        @groups = current_adapter.group_instances(
          @selected_key,
          source: @source,
          limit: 100
        )
      else
        @groups = []
      end
    end

    def show
      @key = string_param(:key)
      @value = string_param(:value)
      return redirect_to groups_path unless @key && @value

      @source = source_param

      events = if @source == :tags
        RailsEventViewer.events.with_tag(@key, @value)
      else
        RailsEventViewer.events.with_context(@key, @value)
      end

      @pagination, @events = paginate(events)
      @total_count = @pagination.count

      @first_event_at, @last_event_at = current_adapter.event_time_span(events)
      @duration = @last_event_at - @first_event_at if @first_event_at && @last_event_at
    end

    private

    def source_param
      params[:source].presence_in(%w[context tags])&.to_sym || :context
    end
  end
end
