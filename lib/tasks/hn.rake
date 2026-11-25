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

  desc "Fetch new posts and refresh the last week's points now (what the hourly job does)"
  task scrape: :environment do
    ScrapeJob.perform_now
  end
end
