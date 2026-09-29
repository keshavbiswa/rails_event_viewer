# frozen_string_literal: true

namespace :rails_event_viewer do
  desc "Delete events older than the configured retention period"
  task cleanup: :environment do
    retention_period = RailsEventViewer.retention_period
    cutoff_time = Time.current - retention_period

    puts "RailsEventViewer: Cleaning up events older than #{cutoff_time}..."

    deleted_count = RailsEventViewer.adapter.delete_before(cutoff_time)

    puts "RailsEventViewer: Deleted #{deleted_count || 'unknown number of'} events."
  end

  desc "Show event statistics"
  task stats: :environment do
    adapter = RailsEventViewer.adapter
    adapter_name = adapter.class.name.split("::").last

    puts ""
    puts "RailsEventViewer Statistics"
    puts "=" * 40
    puts "Storage Adapter: #{adapter_name}"
    puts ""

    total = RailsEventViewer.events.count
    puts "Total Events: #{total}"

    last_hour = adapter.count_since(1.hour.ago) rescue "N/A"
    last_day = adapter.count_since(1.day.ago) rescue "N/A"
    last_week = adapter.count_since(1.week.ago) rescue "N/A"

    puts ""
    puts "Events by Time Period:"
    puts "  Last hour:  #{last_hour}"
    puts "  Last day:   #{last_day}"
    puts "  Last week:  #{last_week}"

    puts ""
    puts "Top 10 Event Types:"
    top_events = adapter.counts_by_name(limit: 10) rescue {}
    if top_events.empty?
      puts "  (no events)"
    else
      top_events.each do |name, count|
        puts "  #{name}: #{count}"
      end
    end

    puts ""
  end

  desc "Clear all events (use with caution!)"
  task clear: :environment do
    adapter = RailsEventViewer.adapter

    if adapter.respond_to?(:clear!)
      print "Are you sure you want to delete ALL events? [y/N] "
      response = $stdin.gets.chomp.downcase

      if response == "y"
        adapter.clear!
        puts "All events have been cleared."
      else
        puts "Cancelled."
      end
    else
      puts "Clear operation not supported by #{adapter.class.name}"
    end
  end

  desc "Flush any buffered events to storage"
  task flush: :environment do
    puts "Flushing buffered events..."

    RailsEventViewer.subscriber.flush!

    puts "Done."
  end
end
