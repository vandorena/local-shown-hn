class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      # From HN (via Algolia)
      t.integer :hn_id, null: false
      t.string :title, null: false
      t.string :url
      t.text :story_text
      t.string :author
      t.integer :points, null: false, default: 0
      t.integer :num_comments, null: false, default: 0
      t.datetime :posted_at, null: false

      # Our pipeline: new -> candidate (a place name matched) -> local / not_local; hidden by hand
      t.string :status, null: false, default: "new"
      t.json :candidate_place_ids, null: false, default: []
      t.references :place, foreign_key: true
      t.float :confidence
      t.text :reason
      t.string :classifier_model
      t.datetime :classified_at
      t.boolean :manual, null: false, default: false # set by the admin page; never reclassified

      t.timestamps
    end
    add_index :posts, :hn_id, unique: true
    add_index :posts, :status
    add_index :posts, :posted_at
  end
end
