require "test_helper"

class PostTest < ActiveSupport::TestCase
  def post(id, points:, comments: 0, age:)
    Post.create!(hn_id: id, title: "Show HN: #{id}", points:, num_comments: comments, posted_at: age.ago, status: "local", confidence: 0.9)
  end

  test "ranked puts a strong recent post over a huge old one, and both over a fresh 1-pointer" do
    fresh_hit = post(1, points: 120, comments: 40, age: 5.days)
    old_classic = post(2, points: 1500, comments: 250, age: 3.years)
    fresh_dud = post(3, points: 1, age: 1.hour)

    assert_equal [ fresh_hit, old_classic, fresh_dud ], Post.ranked.to_a
  end

  test "ranked breaks ties by newest first" do
    older = post(4, points: 1, age: 2.days)
    newer = post(5, points: 1, age: 1.day)

    assert_equal [ newer, older ], Post.ranked.to_a
  end
end
