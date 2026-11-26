# Sends each candidate post to the model, newest first. If the model can't be reached the run stops and the
# posts stay candidates for the next one; a post the model twice answers badly is set aside as not local.
# With an API model, `threads` posts are sent at once; a local model gains nothing from that.
class ClassifyJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "classify", duration: 6.hours

  BATCH = 50

  # Returns how many posts were classified. limit: stop after that many (nil: all). progress: called per post.
  def perform(classifier: LocalClassifier.default, limit: nil, progress: nil, threads: 1)
    done = 0
    # Every post classified leaves the candidate status, so asking again for the newest batch moves on.
    while (limit.nil? || done < limit) &&
          (batch = Post.status_candidate.where(manual: false).order(posted_at: :desc).limit([ BATCH, limit && limit - done ].compact.min).to_a).any?
      batch.each_slice(threads) do |group|
        group.zip(verdicts(classifier, group)).each do |post, verdict|
          post.update!(
            status: verdict.local ? "local" : "not_local", place_id: verdict.place_id, confidence: verdict.confidence,
            reason: verdict.reason, classifier_model: classifier.model, classified_at: Time.current
          )
          done += 1
          progress&.call(post, done)
        end
      end
    end
    done
  rescue LocalClassifier::Unavailable => e
    Rails.logger.warn("classify: #{classifier.model} unavailable after #{done} posts (#{e.message}); the rest wait for the next run")
    done
  end

  private

  # One verdict per post, asked in parallel when there is more than one. Thread#value re-raises, so an
  # Unavailable in any thread stops the run.
  def verdicts(classifier, posts)
    return [ classify(classifier, posts.first) ] if posts.one?

    workers = posts.map { |post| Thread.new { Rails.application.executor.wrap { classify(classifier, post) } } }
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { workers.map(&:value) }
  end

  def classify(classifier, post)
    attempts = 0
    begin
      classifier.classify(post)
    rescue LocalClassifier::BadAnswer => e
      attempts += 1
      retry if attempts < 2
      LocalClassifier::Verdict.new(local: false, place_id: nil, confidence: 0.0, reason: "Model answer unusable: #{e.message}".truncate(500))
    end
  end
end
