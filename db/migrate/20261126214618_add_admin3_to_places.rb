class AddAdmin3ToPlaces < ActiveRecord::Migration[8.1]
  def change
    add_column :places, :admin3, :string
    add_index :places, %i[ country_code admin1 admin2 admin3 ]
  end
end
