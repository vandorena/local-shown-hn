require "test_helper"

class GazetteerLoaderTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/files/geonames").to_s

  setup { @count = GazetteerLoader.new(dir: DIR).load! }

  test "loads towns with their state name and drops historical places" do
    providence = Place.find_by!(geonames_id: 5224151)
    assert_equal "city", providence.kind
    assert_equal "Rhode Island", providence.admin1_name
    assert_equal "Providence, Rhode Island, US", providence.label
    assert_equal "providence-rhode-island-us", providence.slug
    assert_nil Place.find_by(name: "Old Town")
  end

  test "places a county at the population-weighted centre of its towns, and skips counties with none" do
    county = Place.find_by!(name: "Providence County")
    assert_equal "county", county.kind
    assert_equal 190934 + 47408, county.population
    assert_in_delta 41.82, county.lat, 0.02
    assert Place.exists?(name: "Cache County")
    assert Place.exists?(name: "Berks County")
  end

  test "keeps same-named places apart, without countries or states" do
    assert_equal 2, Place.where(name: "Providence").count
    assert_equal 2, Place.where(name: "Reading").count
    assert_empty Place.where(name: [ "Rhode Island", "England", "United States" ])
  end

  test "loading twice updates in place" do
    assert_no_difference("Place.count") { GazetteerLoader.new(dir: DIR).load! }
    assert_equal @count, Place.count
  end
end
