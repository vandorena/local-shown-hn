require "test_helper"

class SiteTest < ActionDispatch::IntegrationTest
  setup do
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    @ri = Place.find_by!(slug: "providence-rhode-island-us")
    @east = Place.find_by!(slug: "east-providence-rhode-island-us")
    @county = Place.find_by!(name: "Providence County")
    @bus = Post.create!(hn_id: 10, title: "Show HN: Providence bus tracker", url: "https://pvdbus.example/",
                        posted_at: 2.days.ago, points: 40, status: "local", place: @ri, confidence: 0.9)
    @zoning = Post.create!(hn_id: 11, title: "Show HN: East Providence zoning lookup", posted_at: 1.day.ago,
                           points: 5, status: "local", place: @east, confidence: 0.8)
    @unsure = Post.create!(hn_id: 12, title: "Show HN: Providence app", posted_at: 1.hour.ago,
                           status: "local", place: @ri, confidence: 0.3)
    @rejected = Post.create!(hn_id: 13, title: "Show HN: Reading list", posted_at: 1.hour.ago, status: "not_local")
  end

  test "the front page lists posts the model is sure of, newest first, under a map" do
    get root_path
    assert_response :success
    assert_select ".post-title a", text: "East Providence zoning lookup"
    assert_select ".post-title a", text: "Providence app", count: 0
    assert_select ".post-title a", text: "Reading list", count: 0
    assert_equal [ "East Providence zoning lookup", "Providence bus tracker" ], css_select(".post-title a").map(&:text)
    assert_select ".map[data-controller=map]"
  end

  test "sorting by points and searching by place" do
    get root_path(sort: "top")
    assert_equal "Providence bus tracker", css_select(".post-title a").first.text

    get root_path(q: "East")
    assert_equal [ "East Providence zoning lookup" ], css_select(".post-title a").map(&:text)

    get root_path(q: "Nowhere%")
    assert_select ".empty"
  end

  test "a town page shows its posts and links to its county; the county page includes its towns" do
    get place_path(@ri)
    assert_response :success
    assert_select "h1", "Providence"
    assert_select "a[href=?]", place_path(@county)
    assert_equal [ "Providence bus tracker" ], css_select(".post-title a").map(&:text)
    assert_select ".nearby a", text: "East Providence"

    get place_path(@county)
    assert_equal 2, css_select(".post-title a").size
  end

  test "a small state's page shows the posts about its towns, and towns link up to it" do
    state = Place.find_by!(kind: "state", name: "Rhode Island")
    get place_path(state)
    assert_response :success
    assert_select "h1", "Rhode Island"
    assert_equal [ "East Providence zoning lookup", "Providence bus tracker" ], css_select(".post-title a").map(&:text)

    get place_path(@ri)
    assert_select "a[href=?]", place_path(state)
  end

  test "the places index groups by country and state" do
    get places_path
    assert_response :success
    assert_select ".country h2", /United States/
    assert_select ".region h3", "Rhode Island"
  end

  test "a post URL that is not http(s) links to the HN thread instead" do
    @bus.update!(url: "javascript:alert(1)")
    get root_path
    assert_select "a[href^=javascript]", count: 0
    assert_select ".post-title a[href=?]", "https://news.ycombinator.com/item?id=10"
  end

  test "an unknown place is a 404" do
    get place_path("nowhere-at-all")
    assert_response :not_found
  end

  test "the Atom feed carries stable HN ids" do
    get feed_path
    assert_response :success
    assert_equal "application/atom+xml", response.media_type
    assert_includes response.body, "tag:news.ycombinator.com,2007:item-10"
    assert_includes response.body, "Providence bus tracker (Providence)"
  end
end
