# Scores the local model against hand labels: bin/rails runner script/eval_classifier.rb [labels.json]
# Labels map hn_id => "local" | "not_local" | "either" (borderline; not counted). Only those posts are run.
# Reclassifies them in place, so it changes the database: use a development copy. SCORE_ONLY=1 skips the run.
path = ARGV.first || Rails.root.join("test/fixtures/files/classifier_labels.json")
labels = JSON.parse(File.read(path)).transform_keys(&:to_i)
posts = Post.where(hn_id: labels.keys, manual: false)
classifier = LocalClassifier.default
started = Time.current
unless ENV["SCORE_ONLY"] == "1"
  posts.update_all(status: "candidate", place_id: nil, confidence: nil, classified_at: nil)
  ClassifyJob.perform_now(classifier:)
end
threshold = Rails.configuration.x.local_threshold
tp = fp = fn = tn = 0
wrong = []
posts.reload.each do |post|
  want = labels[post.hn_id]
  next if want == "either"
  got = post.status_local? && post.confidence.to_f >= threshold
  case [ want == "local", got ]
  when [ true, true ]
    tp += 1
  when [ false, true ]
    fp += 1
    wrong << "FP #{post.confidence} #{post.place&.name}: #{post.short_title}"
  when [ true, false ]
    fn += 1
    wrong << "FN #{post.confidence}: #{post.short_title} (#{post.reason})"
  else
    tn += 1
  end
end
puts wrong.sort
puts "#{classifier.model} at threshold #{threshold}: precision #{(tp.to_f / [ tp + fp, 1 ].max).round(2)}, " \
     "recall #{(tp.to_f / [ tp + fn, 1 ].max).round(2)} (tp #{tp} fp #{fp} fn #{fn} tn #{tn}), #{(Time.current - started).round}s"
