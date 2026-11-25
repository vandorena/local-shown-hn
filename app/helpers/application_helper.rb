module ApplicationHelper
  HN_ITEM = "https://news.ycombinator.com/item?id=".freeze

  # Where a post's title links: its own URL when that is http(s), else its HN thread.
  def post_link(post) = safe_url(post.url) || hn_link(post)

  def hn_link(post) = "#{HN_ITEM}#{post.hn_id.to_i}"

  # "example.com" for a post's link, or nil for a text-only post.
  def post_host(post) = safe_url(post.url) && URI.parse(post.url).host&.delete_prefix("www.")

  private

  # The URL if it is a well-formed http(s) one; HN only allows those, but we don't rely on it.
  def safe_url(url)
    return nil if url.blank?
    uri = URI.parse(url)
    url if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end
end
