require "test_helper"

class PostTransferTest < ActiveSupport::TestCase
  setup do
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    @ri = Place.find_by!(slug: "providence-rhode-island-us")
    @ut = Place.find_by!(slug: "providence-utah-us")
  end

  def export
    io = StringIO.new("".b)
    PostTransfer.new.export(io)
    io.string
  end

  def import(data) = PostTransfer.new.import(StringIO.new(data))

  test "round-trips posts and verdicts, naming places by GeoNames id" do
    Post.create!(hn_id: 1, title: "Show HN: Providence bus tracker", posted_at: Time.utc(2026, 11, 1), points: 12,
                 status: "local", place: @ri, candidate_place_ids: [ @ri.id, @ut.id ], confidence: 0.9,
                 reason: "Buses.", classifier_model: "qwen3:8b", classified_at: Time.utc(2026, 11, 2))
    Post.create!(hn_id: 2, title: "Show HN: A JSON parser", posted_at: Time.utc(2026, 11, 3), status: "not_local")
    data = export
    line = JSON.parse(Zlib::GzipReader.new(StringIO.new(data)).each_line.first)
    assert_equal 5224151, line["place"]

    # A fresh database, with places loaded in a different order, so the ids differ.
    Post.delete_all
    Place.delete_all
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    assert_equal 2, import(data)

    post = Post.find_by!(hn_id: 1)
    assert_equal "providence-rhode-island-us", post.place.slug
    assert_equal %w[ providence-rhode-island-us providence-utah-us ], Place.find(post.candidate_place_ids).map(&:slug).sort
    assert_equal "qwen3:8b", post.classifier_model
    assert_equal Time.utc(2026, 11, 1), post.posted_at
    assert Post.find_by!(hn_id: 2).status_not_local?
  end

  test "keeps verdicts set by hand on the receiving side, but takes fresh points" do
    Post.create!(hn_id: 1, title: "Show HN: Providence bus tracker", posted_at: Time.current, points: 50,
                 status: "local", place: @ri, confidence: 0.9)
    data = export
    Post.find_by!(hn_id: 1).update!(status: "hidden", manual: true, points: 1)

    import(data)
    post = Post.find_by!(hn_id: 1)
    assert post.status_hidden?
    assert post.manual?
    assert_equal 50, post.points
  end
end
