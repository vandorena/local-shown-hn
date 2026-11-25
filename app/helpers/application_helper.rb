module ApplicationHelper
  # "example.com" for a post's link, or nil for a text-only post.
  def post_host(post)
    return nil if post.url.blank?
    URI.parse(post.url).host&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end
end
