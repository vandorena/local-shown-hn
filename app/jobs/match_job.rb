# Runs PlaceMatcher over every post still marked new: a post with candidate places goes on to the local
# model (ClassifyJob), and the rest are not_local. Posts set by hand are never touched.
class MatchJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "match", duration: 1.hour

  BATCH = 1_000

  # Returns [matched, candidates].
  def perform(matcher: PlaceMatcher.instance)
    matched = candidates = 0
    Post.status_new.where(manual: false).in_batches(of: BATCH) do |batch|
      found = batch.pluck(:id, :title, :story_text, :url).to_h do |id, title, text, url|
        [ id, matcher.candidates(title:, text:, url:) ]
      end
      hits, misses = found.partition { |_, ids| ids.any? }
      Post.transaction do
        hits.each { |id, ids| Post.where(id:).update_all(status: "candidate", candidate_place_ids: ids, updated_at: Time.current) }
        Post.where(id: misses.map(&:first)).update_all(status: "not_local", candidate_place_ids: [], updated_at: Time.current)
      end
      matched += found.size
      candidates += hits.size
    end
    Rails.logger.info("match: #{matched} posts, #{candidates} candidates")
    [ matched, candidates ]
  end
end
