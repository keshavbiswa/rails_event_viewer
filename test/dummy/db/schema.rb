# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2024_12_08_000001) do
  create_table "rails_event_viewer_entries", force: :cascade do |t|
    t.string "name", null: false
    t.json "payload", default: {}
    t.json "tags", default: {}
    t.json "context", default: {}
    t.string "source_file"
    t.integer "source_line"
    t.string "source_label"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_rails_event_viewer_entries_on_name"
    t.index ["occurred_at"], name: "index_rails_event_viewer_entries_on_occurred_at"
    t.index ["name", "occurred_at"], name: "index_rails_event_viewer_entries_on_name_and_occurred_at"
  end
end
