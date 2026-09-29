# frozen_string_literal: true

module RailsEventViewer
  module TimeUtils
    module_function

    def truncate_to_interval(time, interval)
      return nil unless time

      case interval
      when :minute
        time.beginning_of_minute
      when :hour
        time.beginning_of_hour
      when :day
        time.beginning_of_day
      when :week
        time.beginning_of_week
      else
        time.beginning_of_hour
      end
    end
  end
end
