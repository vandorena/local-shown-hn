require "test_helper"

class PlaceMatcherTest < ActiveSupport::TestCase
  setup do
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    @matcher = PlaceMatcher.new(common: %w[ reading mobile providence ].to_set, tech: %w[ phoenix ].to_set)
  end

  def labels(title, text: nil, url: nil)
    Place.find(@matcher.candidates(title:, text:, url:)).index_by(&:id)
         .values_at(*@matcher.candidates(title:, text:, url:)).map(&:label)
  end

  def first(title, **) = labels(title, **).first

  # [title, text, url, the place expected first (nil: no candidates)]
  CASES = [
    [ "Show HN: Reading list app for Kindle", nil, nil, nil ],
    [ "Show HN: Reading, PA bus times", nil, nil, "Reading, Pennsylvania, United States" ],
    [ "Show HN: Reading, UK council meeting tracker", nil, nil, "Reading, England, United Kingdom" ],
    [ "Show HN: Phoenix LiveView component library", nil, nil, nil ],
    [ "Show HN: Parking map for Phoenix, AZ", nil, nil, "Phoenix, Arizona, United States" ],
    [ "Show HN: Providence bus tracker", nil, nil, "Providence, Rhode Island, United States" ],
    [ "Show HN: Providence app", nil, nil, nil ],
    [ "Show HN: Trail map for Providence, Utah", nil, nil, "Providence, Utah, United States" ],
    [ "Show HN: East Providence zoning lookup", nil, nil, "East Providence, Rhode Island, United States" ],
    [ "Show HN: Providence County property records", nil, nil, "Providence County, Rhode Island, United States" ],
    [ "Show HN: Mobile app for budgeting", nil, nil, nil ],
    [ "Show HN: Provo restaurant finder", nil, nil, "Provo, Utah, United States" ],
    [ "Show HN: a provo thing", nil, nil, nil ],
    [ "Show HN: Show HN: Provo food trucks", nil, nil, "Provo, Utah, United States" ],
    [ "Show HN: Bus arrival times", nil, "https://providence-buses.org/", "Providence, Rhode Island, United States" ],
    [ "Show HN: Restaurant finder", nil, "https://provoeats.com/", nil ],
    [ "Show HN: Restaurant finder for my town", nil, "https://provoeats.com/", "Provo, Utah, United States" ],
    [ "Show HN: Live arrivals", nil, "https://eastprovidencebus.org/", "East Providence, Rhode Island, United States" ],
    [ "Show HN: Pixel-art map of downtown", nil, "https://isoprovo.app/", "Provo, Utah, United States" ],
    [ "Show HN: Speed reading", nil, "https://readingfast.app/", nil ],
    [ "Show HN: Phone builds", nil, "https://mobilebuilds.dev/", nil ],
    [ "Show HN: A transit app", "<p>Providence has slow buses.", nil, nil ],
    [ "Show HN: A transit app", "I live in Providence and the buses are slow.", nil, "Providence, Rhode Island, United States" ],
    [ "Show HN: Budgeting for us, by us", nil, nil, nil ]
  ].freeze

  test "a name that is also a state counts only with a qualifier, unless the place is in that state" do
    suburb = Place.create!(geonames_id: 9_000_001, name: "United Kingdom", ascii_name: "United Kingdom", kind: "city",
                           country_code: "AU", admin1: "07", admin1_name: "Victoria", country_name: "Australia",
                           lat: -37.8, lng: 145.2, population: 250_000, slug: "united-kingdom-victoria-au")
    capital = Place.create!(geonames_id: 9_000_002, name: "Victoria", ascii_name: "Victoria", kind: "city",
                            country_code: "AU", admin1: "07", admin1_name: "Victoria", country_name: "Australia",
                            lat: -37.8, lng: 145.0, population: 300_000, slug: "victoria-victoria-au")
    matcher = PlaceMatcher.new(common: Set.new, tech: Set.new)

    assert_empty matcher.candidates(title: "Show HN: United Kingdom bus tracker")
    assert_equal suburb.id, matcher.candidates(title: "Show HN: Bus tracker for United Kingdom, Victoria").first
    assert_equal Place.find_by!(kind: "state", name: "Rhode Island").id, matcher.candidates(title: "Show HN: Rhode Island bus tracker").first
    assert_equal [ capital.id ], matcher.candidates(title: "Show HN: Victoria bus tracker")
  end

  test "a district matches by its short name, inside a hostname too" do
    district = Place.find_by!(name: "Cherwell District")
    matcher = PlaceMatcher.new(common: Set.new, tech: Set.new)
    assert_equal district.id, matcher.candidates(title: "Show HN: Cherwell council planning tracker").first
    assert_equal district.id, matcher.candidates(title: "Show HN: Drive around my village in 3D", url: "https://cherwellvalleymotorclub.app").first
  end

  CASES.each do |title, text, url, expected|
    test "#{title} #{text} #{url} => #{expected || 'nothing'}" do
      if expected
        assert_equal expected, first(title, text:, url:)
      else
        assert_empty labels(title, text:, url:)
      end
    end
  end

  test "normalizes accents, apostrophes and hyphens" do
    assert_equal "sao paulo", PlaceMatcher.normalize("São Paulo")
    assert_equal "wilkes barre", PlaceMatcher.normalize("Wilkes-Barre")
    assert_equal "coeur dalene", PlaceMatcher.normalize("Coeur d'Alene")
  end

  test "returns no more than five candidates" do
    title = "Show HN: Providence, Reading, Mobile, Phoenix, Provo, New Castle and East Providence city guides"
    assert_operator @matcher.candidates(title:).size, :<=, PlaceMatcher::MAX_CANDIDATES
  end
end
