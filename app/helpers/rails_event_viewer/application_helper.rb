module RailsEventViewer
  module ApplicationHelper
    def nav_link(label, path, controller)
      active = controller_name == controller
      state_classes = active ? "bg-indigo-700 text-white" : "text-indigo-200 hover:bg-indigo-500 hover:text-white"

      link_to label, path, class: "rounded-md px-3 py-2 text-sm font-medium #{state_classes}", aria: { current: ("page" if active) }
    end

    def format_event_time(event)
      time = event[:occurred_at]
      return "N/A" unless time

      time.in_time_zone.strftime("%Y-%m-%d %H:%M:%S.%3N")
    end

    def time_ago_with_title(time)
      return "N/A" unless time

      content_tag(:span, time_ago_in_words(time) + " ago", title: time.in_time_zone.strftime("%Y-%m-%d %H:%M:%S %Z"))
    end

    def truncate_json(json, length: 100)
      text = json.is_a?(Hash) ? JSON.generate(json) : json.to_s
      truncate(text, length: length)
    end

    def json_tree(data)
      return content_tag(:span, "null", class: "text-gray-500") if data.nil?
      return content_tag(:span, JSON.generate(data), class: json_value_class(data)) unless data.is_a?(Hash) || data.is_a?(Array)

      data.is_a?(Hash) ? render_hash_tree(data) : render_array_tree(data)
    end

    def page_path(page)
      "#{request.path}?#{request.query_parameters.merge("page" => page.to_s).to_query}"
    end

    def event_payload(event)
      event[:payload] || {}
    end

    def event_tags(event)
      event[:tags] || {}
    end

    def event_context(event)
      event[:context] || {}
    end

    def event_short_filepath(event)
      filepath = event[:source_file]
      return nil unless filepath

      filepath.gsub(%r{.*/app/}, "app/")
    end

    def format_duration(seconds)
      return "-" unless seconds

      duration = ActiveSupport::Duration.build(seconds)
      parts = duration.parts

      return "0 seconds" if parts.empty? || parts == { seconds: 0 }

      parts.map { |unit, value|
        unit_name = value == 1 ? unit.to_s.singularize : unit.to_s
        "#{value} #{unit_name}"
      }.to_sentence
    end

    private

    def json_value_class(value)
      case value
      when String
        "text-green-600"
      when Numeric
        "text-blue-600"
      when TrueClass, FalseClass
        "text-purple-600"
      else
        "text-gray-900"
      end
    end

    def render_hash_tree(hash)
      return content_tag(:span, "{}", class: "text-gray-500") if hash.empty?

      content_tag(:div, class: "pl-4") do
        hash.map do |key, value|
          content_tag(:div, class: "py-0.5") do
            content_tag(:span, "#{key}:", class: "text-gray-600 font-medium mr-2") +
              json_tree(value)
          end
        end.join.html_safe
      end
    end

    def render_array_tree(array)
      return content_tag(:span, "[]", class: "text-gray-500") if array.empty?

      content_tag(:div, class: "pl-4") do
        array.each_with_index.map do |value, index|
          content_tag(:div, class: "py-0.5") do
            content_tag(:span, "[#{index}]:", class: "text-gray-500 mr-2") +
              json_tree(value)
          end
        end.join.html_safe
      end
    end
  end
end
