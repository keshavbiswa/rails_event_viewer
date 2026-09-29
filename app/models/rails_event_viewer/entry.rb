module RailsEventViewer
  class Entry < ApplicationRecord
    self.table_name = "rails_event_viewer_entries"

    validates :name, presence: true
    validates :occurred_at, presence: true

    def source_location
      {
        filepath: source_file,
        lineno: source_line,
        label: source_label
      }.compact
    end

    def short_filepath
      return nil unless source_file

      source_file.gsub(%r{.*/app/}, "app/")
    end

    def tagged?
      tags.present? && tags.any?
    end

    def has_context?
      context.present? && context.any?
    end

    def tag(key)
      tags&.dig(key.to_s)
    end
  end
end
