class CreateRailsEventViewerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :rails_event_viewer_entries do |t|
      t.string :name, null: false

      # Use jsonb for PostgreSQL (better performance), json for others (SQLite, MySQL)
      json_type = postgresql? ? :jsonb : :json
      json_options = mysql? ? {} : { default: {} }
      t.column :payload, json_type, **json_options
      t.column :tags, json_type, **json_options
      t.column :context, json_type, **json_options

      t.string :source_file
      t.integer :source_line
      t.string :source_label
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :rails_event_viewer_entries, :occurred_at
    add_index :rails_event_viewer_entries, [:name, :occurred_at]

    # GIN index for JSONB columns (PostgreSQL only)
    if postgresql?
      add_index :rails_event_viewer_entries, :tags, using: :gin
      add_index :rails_event_viewer_entries, :context, using: :gin
    end
  end

  private

  def postgresql?
    connection.adapter_name.downcase.include?("postgresql")
  end

  def mysql?
    connection.adapter_name.match?(/mysql|trilogy/i)
  end
end
