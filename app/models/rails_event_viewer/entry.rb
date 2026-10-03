module RailsEventViewer
  class Entry < ApplicationRecord
    self.table_name = "rails_event_viewer_entries"

    validates :name, presence: true
    validates :occurred_at, presence: true
  end
end
