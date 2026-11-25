require "test_helper"

class MatchJobTest < ActiveJob::TestCase
  setup do
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    @matcher = PlaceMatcher.new(common: %w[ providence ].to_set, tech: Set.new)
  end

  def post(title, **attrs) = Post.create!(hn_id: Post.count + 1, title:, posted_at: Time.current, **attrs)

  test "marks posts with place names as candidates and the rest as not local" do
    local = post("Show HN: Providence bus tracker")
    other = post("Show HN: A faster JSON parser")

    assert_equal [ 2, 1 ], MatchJob.perform_now(matcher: @matcher)
    assert local.reload.status_candidate?
    assert_equal Place.find_by!(slug: "providence-rhode-island-us").id, local.candidate_place_ids.first
    assert other.reload.status_not_local?
  end

  test "leaves posts set by hand and posts already matched alone" do
    manual = post("Show HN: Providence bus tracker", status: "new", manual: true)
    done = post("Show HN: Provo restaurant finder", status: "not_local")
    MatchJob.perform_now(matcher: @matcher)
    assert manual.reload.status_new?
    assert done.reload.status_not_local?
  end
end
