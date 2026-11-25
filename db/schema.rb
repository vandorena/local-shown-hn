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

ActiveRecord::Schema[8.1].define(version: 2026_11_25_045623) do
  create_table "places", force: :cascade do |t|
    t.integer "geonames_id", null: false
    t.string "name", null: false
    t.string "ascii_name", null: false
    t.string "kind", null: false
    t.string "country_code", null: false
    t.string "admin1"
    t.string "admin1_name"
    t.string "admin2"
    t.float "lat", null: false
    t.float "lng", null: false
    t.integer "population", default: 0, null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ascii_name"], name: "index_places_on_ascii_name"
    t.index ["geonames_id"], name: "index_places_on_geonames_id", unique: true
    t.index ["slug"], name: "index_places_on_slug", unique: true
  end

  create_table "posts", force: :cascade do |t|
    t.integer "hn_id", null: false
    t.string "title", null: false
    t.string "url"
    t.text "story_text"
    t.string "author"
    t.integer "points", default: 0, null: false
    t.integer "num_comments", default: 0, null: false
    t.datetime "posted_at", null: false
    t.string "status", default: "new", null: false
    t.json "candidate_place_ids", default: [], null: false
    t.integer "place_id"
    t.float "confidence"
    t.text "reason"
    t.string "classifier_model"
    t.datetime "classified_at"
    t.boolean "manual", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hn_id"], name: "index_posts_on_hn_id", unique: true
    t.index ["place_id"], name: "index_posts_on_place_id"
    t.index ["posted_at"], name: "index_posts_on_posted_at"
    t.index ["status"], name: "index_posts_on_status"
  end

  add_foreign_key "posts", "places"
end
