# Upserts Algolia hits into posts. HN's fields (title, points...) are refreshed every time; the pipeline
# fields are left alone, except that a post whose title or text changed is sent back to be matched again.
class PostImporter
  HN_FIELDS = %i[ title url story_text author points num_comments posted_at ].freeze

  # Returns how many hits were written.
  def import(hits)
    rows = hits.filter_map { row(it) }
    return 0 if rows.empty?

    changed = changed_text(rows)
    now = Time.current
    Post.upsert_all(rows.map { it.merge(created_at: now, updated_at: now) }, unique_by: :hn_id, update_only: HN_FIELDS)
    Post.where(hn_id: changed, manual: false).update_all(status: "new", updated_at: now) if changed.any?
    rows.size
  end

  private

  def row(hit)
    return nil if hit["title"].blank? || hit["created_at_i"].blank?

    {
      hn_id: hit["objectID"].to_i,
      title: hit["title"],
      url: hit["url"].presence,
      story_text: hit["story_text"].presence,
      author: hit["author"],
      points: hit["points"].to_i,
      num_comments: hit["num_comments"].to_i,
      posted_at: Time.at(hit["created_at_i"]).utc
    }
  end

  # hn_ids of posts we already have whose title or text is different now (people edit Show HN posts).
  def changed_text(rows)
    by_id = rows.index_by { it[:hn_id] }
    Post.where(hn_id: by_id.keys).pluck(:hn_id, :title, :story_text).filter_map do |hn_id, title, text|
      hn_id if by_id[hn_id][:title] != title || by_id[hn_id][:story_text] != text
    end
  end
end
