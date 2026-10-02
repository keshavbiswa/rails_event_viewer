# frozen_string_literal: true

module RailsEventViewer
  module TimeUtils
    module_function

    def truncate_to_interval(time, interval)
      return nil unless time

      case interval
      when :hour then time.beginning_of_hour
      when :day then time.beginning_of_day
      else raise ArgumentError, "Unknown interval: #{interval.inspect}"
      end
    end
  end
end
