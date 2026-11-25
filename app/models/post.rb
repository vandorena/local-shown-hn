# A Show HN submission. HN's fields are refreshed by every scrape; the pipeline fields are ours.
class Post < ApplicationRecord
  belongs_to :place, optional: true

  enum :status, { new: "new", candidate: "candidate", local: "local", not_local: "not_local", hidden: "hidden" },
       prefix: true, validate: true

  validates :hn_id, :title, :posted_at, presence: true

  def hn_url = "https://news.ycombinator.com/item?id=#{hn_id}"

  # The title without its "Show HN:" prefix, which every post here has.
  def short_title = title.sub(/\AShow HN:\s*/i, "")
end
