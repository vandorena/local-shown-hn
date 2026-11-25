# Moves posts and their verdicts between databases as gzipped JSON lines, so the slow part (running the
# model over the whole history) can happen on a laptop and the result can be loaded onto the server.
# Places are named by GeoNames id, since row ids differ between databases; both sides need the places table.
require "zlib"

class PostTransfer
  FIELDS = %w[ hn_id title url story_text author points num_comments posted_at status confidence reason
               classifier_model classified_at manual ].freeze
  BATCH = 2_000
  VERDICT_COLUMNS = (PostImporter::HN_FIELDS + %i[ status place_id candidate_place_ids confidence reason
                                                 classifier_model classified_at manual ]).freeze

  # Writes every post to `io`. Returns how many.
  def export(io)
    geonames = Place.pluck(:id, :geonames_id).to_h
    gz = Zlib::GzipWriter.new(io)
    count = 0
    Post.in_batches(of: BATCH) do |batch|
      batch.pluck(*FIELDS, :place_id, :candidate_place_ids).each do |*values, place_id, candidates|
        row = FIELDS.zip(values).to_h
        row["posted_at"] = row["posted_at"]&.iso8601
        row["classified_at"] = row["classified_at"]&.iso8601
        row["place"] = geonames[place_id]
        row["candidates"] = Array(candidates).filter_map { geonames[it] }
        gz.puts(row.to_json)
        count += 1
      end
    end
    gz.finish
    count
  end

  # Upserts the posts in `io`. A post set by hand here keeps its verdict; everything else takes the file's.
  # Returns how many rows were read.
  def import(io)
    raise "no places loaded; run bin/rails places:refresh first" if Place.none?

    places = Place.pluck(:geonames_id, :id).to_h
    count = 0
    Zlib::GzipReader.new(io).each_line.each_slice(BATCH) do |lines|
      rows = lines.map { row(JSON.parse(it), places) }
      manual_here = Post.where(hn_id: rows.pluck(:hn_id), manual: true).pluck(:hn_id).to_set
      verdicts, hn_only = rows.partition { !manual_here.include?(it[:hn_id]) }
      now = Time.current
      upsert(verdicts, now, update_only: VERDICT_COLUMNS)
      upsert(hn_only, now, update_only: PostImporter::HN_FIELDS)
      count += rows.size
    end
    count
  end

  private

  def row(data, places)
    {
      hn_id: data.fetch("hn_id"), title: data.fetch("title"), url: data["url"], story_text: data["story_text"],
      author: data["author"], points: data["points"].to_i, num_comments: data["num_comments"].to_i,
      posted_at: Time.iso8601(data.fetch("posted_at")), status: data["status"] || "new",
      place_id: places[data["place"]], candidate_place_ids: Array(data["candidates"]).filter_map { places[it] },
      confidence: data["confidence"], reason: data["reason"], classifier_model: data["classifier_model"],
      classified_at: data["classified_at"] && Time.iso8601(data["classified_at"]), manual: data["manual"] == true
    }.tap do |r|
      # A verdict whose place this database doesn't have can't be shown; send it back to be matched here.
      r.merge!(status: "new", place_id: nil) if r[:status] == "local" && r[:place_id].nil?
    end
  end

  def upsert(rows, now, update_only:)
    return if rows.empty?
    Post.upsert_all(rows.map { it.merge(created_at: now, updated_at: now) }, unique_by: :hn_id, update_only:)
  end
end
