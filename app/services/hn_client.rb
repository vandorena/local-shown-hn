# Reads Show HN stories from the Algolia HN Search API (https://hn.algolia.com/api), newest first.
#
# Algolia returns at most 1,000 hits per query however it is paged, so we walk backwards in time instead:
# each request asks for stories at or before the oldest one seen so far. Ties on the same second are
# fetched twice and dropped by id, so none are lost.
require "net/http"

class HnClient
  URL = "https://hn.algolia.com/api/v1/search_by_date".freeze
  PER_PAGE = 1_000

  # get: takes a URI and returns the response body (tests pass a fake). pause: seconds between requests.
  def initialize(get: method(:http_get), pause: 0.5)
    @get = get
    @pause = pause
  end

  # Yields pages of hits (arrays of hashes), newest first, from `before` (default: now) back to `after`
  # (default: the first Show HN). Both are Times; `after` is exclusive.
  def each_page(before: nil, after: nil)
    return enum_for(:each_page, before:, after:) unless block_given?

    seen = Set.new
    upper = before&.to_i
    loop do
      page = fetch(upper:, lower: after&.to_i)
      break if page.empty?

      oldest = page.map { it["created_at_i"] }.min
      hits = page.reject { seen.include?(it["objectID"]) }
      if hits.empty?
        # The whole page is the second we stopped at, seen already. Step past it. That only drops posts
        # when more than PER_PAGE of them share one second, which HN never has.
        upper = oldest - 1
      else
        hits.each { seen << it["objectID"] }
        yield hits
        upper = oldest
      end
      sleep @pause if @pause.positive?
    end
  end

  private

  def fetch(upper:, lower:)
    filters = []
    filters << "created_at_i<=#{upper}" if upper
    filters << "created_at_i>#{lower}" if lower
    uri = URI(URL)
    uri.query = URI.encode_www_form({ tags: "story,show_hn", hitsPerPage: PER_PAGE, numericFilters: filters.join(",").presence }.compact)
    JSON.parse(@get.call(uri)).fetch("hits")
  end

  def http_get(uri)
    attempts = 0
    begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        response = http.request_get(uri.request_uri)
        response.value
        response.body
      end
    rescue Net::HTTPExceptions, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError
      attempts += 1
      raise if attempts > 4
      sleep 2**attempts
      retry
    end
  end
end
