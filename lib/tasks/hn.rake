namespace :hn do
  desc "Fetch every Show HN post into posts (SINCE=2026-10-01 / UNTIL=... to limit; safe to rerun)"
  task backfill: :environment do
    after = ENV["SINCE"].presence && Time.zone.parse(ENV["SINCE"])
    before = ENV["UNTIL"].presence && Time.zone.parse(ENV["UNTIL"])
    importer = PostImporter.new
    total = 0
    HnClient.new.each_page(before:, after:) do |hits|
      total += importer.import(hits)
      oldest = Time.at(hits.map { it["created_at_i"] }.min).utc
      puts "hn: #{total} posts, back to #{oldest.to_date}"
    end
    puts "hn: done, #{total} posts fetched; #{Post.count} in the database"
  end

  desc "Look for place names in every post still marked new (RESET=1 to redo every post not set by hand)"
  task match: :environment do
    Post.where(manual: false).where.not(status: "new").update_all(status: "new") if ENV["RESET"] == "1"
    matched, candidates = MatchJob.perform_now(classify: false)
    puts "hn: matched #{matched} posts, #{candidates} candidates"
  end

  desc "Fetch new posts and refresh the last week's points now (what the hourly job does)"
  task scrape: :environment do
    ScrapeJob.perform_now
  end

  desc "Send candidate posts to the local model, newest first (LIMIT=100 to stop early; Ctrl-C is safe)"
  task classify: :environment do
    classifier = LocalClassifier.default
    threads = Integer(ENV.fetch("THREADS") { classifier.is_a?(ClaudeClassifier) ? 4 : 1 })
    total = Post.status_candidate.where(manual: false).count
    started = Time.current
    puts "hn: #{total} candidates, model #{classifier.model}, #{threads} at a time"
    done = ClassifyJob.perform_now(classifier:, threads:, limit: ENV["LIMIT"]&.to_i, progress: lambda { |post, n|
      rate = n / (Time.current - started)
      verdict = post.status_local? ? "LOCAL #{post.place&.label} (#{post.confidence})" : "no"
      puts "[#{n}/#{total} #{rate.round(2)}/s] #{post.short_title.truncate(60)} => #{verdict}"
    })
    puts "hn: classified #{done}; #{Post.status_candidate.count} candidates left, #{Post.shown.count} shown"
  end

  desc "Write every post and verdict as gzipped JSON lines (FILE=posts.jsonl.gz, default stdout)"
  task export: :environment do
    path = ENV["FILE"].presence
    count = path ? File.open(path, "wb") { PostTransfer.new.export(it) } : PostTransfer.new.export($stdout.binmode)
    warn "hn: exported #{count} posts#{" to #{path}" if path}"
  end

  desc "Load posts and verdicts from hn:export (FILE=posts.jsonl.gz, default stdin); safe to rerun"
  task import: :environment do
    path = ENV["FILE"].presence
    count = path ? File.open(path, "rb") { PostTransfer.new.import(it) } : PostTransfer.new.import($stdin.binmode)
    warn "hn: imported #{count} posts; #{Post.shown.count} shown, #{Post.status_candidate.count} waiting for the model"
  end
end
