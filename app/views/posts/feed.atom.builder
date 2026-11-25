atom_feed(language: "en") do |feed|
  feed.title "Local Show HN"
  feed.subtitle "Show HN projects tied to a city, town or county"
  feed.updated @posts.first&.posted_at || Time.current

  @posts.each do |post|
    feed.entry(post, id: "tag:news.ycombinator.com,2007:item-#{post.hn_id}", url: post.url.presence || post.hn_url,
                     published: post.posted_at, updated: post.posted_at) do |entry|
      entry.title "#{post.short_title} (#{post.place.name})"
      entry.content <<~HTML, type: "html"
        <p>#{ERB::Util.h(post.place.label)} · #{post.points} points ·
        <a href="#{post.hn_url}">#{post.num_comments} comments on HN</a></p>
      HTML
      entry.author { |author| author.name post.author.to_s }
    end
  end
end
