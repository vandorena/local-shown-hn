require "test_helper"

class PostImporterTest < ActiveSupport::TestCase
  def hits = JSON.parse(file_fixture("algolia/page1.json").read)["hits"]

  test "imports Algolia hits" do
    assert_equal 3, PostImporter.new.import(hits)
    post = Post.find_by!(hn_id: 50638523)
    assert_equal "Show HN: U.S. Interstate Weather", post.title
    assert_equal "U.S. Interstate Weather", post.short_title
    assert_equal "https://www.interstateweather.com/", post.url
    assert_equal Time.at(1795581332).utc, post.posted_at
    assert post.status_new?
  end

  test "refreshes points without touching the pipeline fields" do
    PostImporter.new.import(hits)
    post = Post.find_by!(hn_id: 50638523)
    post.update!(status: "not_local", confidence: 0.9)

    PostImporter.new.import(hits.map { it.merge("points" => 99) })
    post.reload
    assert_equal 99, post.points
    assert post.status_not_local?
  end

  test "sends a post back to matching when its title changes, unless it was set by hand" do
    PostImporter.new.import(hits)
    edited, manual = Post.where(hn_id: [ 50638523, 50638565 ]).order(:hn_id).to_a
    edited.update!(status: "not_local")
    manual.update!(status: "local", manual: true)

    PostImporter.new.import(hits.map { it.merge("title" => "#{it['title']} (edited)") })
    assert edited.reload.status_new?
    assert manual.reload.status_local?
  end
end
