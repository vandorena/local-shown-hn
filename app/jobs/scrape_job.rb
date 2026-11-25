# Hourly (config/recurring.yml): fetches new Show HN posts and refreshes points and comment counts for
# the last week's, then hands anything new to the place matcher.
class ScrapeJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "scrape", duration: 30.minutes

  REFRESH_WINDOW = 7.days

  def perform(client: HnClient.new)
    # Reach back far enough to catch anything posted since the last scrape, and at least a week for points.
    latest = Post.maximum(:posted_at)
    after = [ latest, REFRESH_WINDOW.ago ].compact.min
    importer = PostImporter.new
    count = client.each_page(after:).sum { importer.import(it) }
    Rails.logger.info("scrape: #{count} posts since #{after.utc.iso8601}")
    MatchJob.perform_later if Post.status_new.exists?
  end
end
