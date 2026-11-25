class AddCountryNameToPlaces < ActiveRecord::Migration[8.1]
  def change
    add_column :places, :country_name, :string
  end
end
