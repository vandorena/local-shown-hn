class CreatePlaces < ActiveRecord::Migration[8.1]
  def change
    create_table :places do |t|
      t.integer :geonames_id, null: false
      t.string :name, null: false
      t.string :ascii_name, null: false
      t.string :kind, null: false # "city" or "county"
      t.string :country_code, null: false
      t.string :admin1 # GeoNames admin1 code, e.g. "RI"
      t.string :admin1_name # e.g. "Rhode Island"
      t.string :admin2 # GeoNames admin2 code; for a county, its own code
      t.float :lat, null: false
      t.float :lng, null: false
      t.integer :population, null: false, default: 0
      t.string :slug, null: false
      t.timestamps
    end
    add_index :places, :geonames_id, unique: true
    add_index :places, :slug, unique: true
    add_index :places, :ascii_name
  end
end
