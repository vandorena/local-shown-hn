# A Show HN submission. HN's fields are refreshed by every scrape; the pipeline fields are ours.
class Post < ApplicationRecord
  belongs_to :place, optional: true

  enum :status, { new: "new", candidate: "candidate", local: "local", not_local: "not_local", hidden: "hidden" },
       prefix: true, validate: true

  validates :hn_id, :title, :posted_at, presence: true

  # What the site shows: posts the model is sure enough about, and any marked local by hand.
  scope :shown, lambda {
    status_local.where(manual: true).or(status_local.where(confidence: Rails.configuration.x.local_threshold..)).where.not(place_id: nil)
  }

  # The "top" order: HN's points-over-age idea, slowed down for a site that gets a few posts a week.
  # score = (points - 1 + comments / 2) / (age in weeks + 2) ^ GRAVITY
  # Comments count for half a point (people talking about it); the submitter's own point doesn't count.
  # Age is in weeks rather than HN's hours, so a strong post stays near the top for a few weeks
  # and the big all-time posts still outrank last week's 1-pointers.
  GRAVITY = 1.2

  scope :ranked, lambda { |now = Time.current|
    age_weeks = "(julianday(#{connection.quote(now.utc.to_fs(:db))}) - julianday(posts.posted_at)) / 7.0"
    order(Arel.sql("(MAX(posts.points - 1, 0) + posts.num_comments * 0.5) / pow(MAX(#{age_weeks}, 0) + 2, #{GRAVITY}) DESC, posts.posted_at DESC"))
  }

  def hn_url = "https://news.ycombinator.com/item?id=#{hn_id}"

  # The title without its "Show HN:" prefix, which every post here has.
  def short_title = title.sub(/\AShow HN:\s*/i, "")
end
