require "test_helper"

class HnClientTest < ActiveSupport::TestCase
  # Answers like Algolia: newest first, at most `per_page`, honouring the created_at_i filters.
  class FakeAlgolia
    attr_reader :queries

    def initialize(hits, per_page: 2)
      @hits = hits.sort_by { -it["created_at_i"] }
      @per_page = per_page
      @queries = []
    end

    def call(uri)
      params = URI.decode_www_form(uri.query).to_h
      @queries << params
      filters = params["numericFilters"].to_s.split(",")
      hits = @hits.select do |hit|
        filters.all? do |f|
          op, value = f.match(/created_at_i(<=|>)(\d+)/).captures
          op == "<=" ? hit["created_at_i"] <= value.to_i : hit["created_at_i"] > value.to_i
        end
      end
      { hits: hits.first(@per_page) }.to_json
    end
  end

  def hit(id, at) = { "objectID" => id.to_s, "created_at_i" => at, "title" => "Show HN: #{id}" }

  test "walks backwards past the per-query limit, keeping posts that share a second" do
    hits = [ hit(1, 100), hit(2, 200), hit(3, 200), hit(4, 200), hit(5, 300), hit(6, 50) ]
    fake = FakeAlgolia.new(hits, per_page: 3)
    ids = HnClient.new(get: fake, pause: 0).each_page.flat_map { |page| page.map { it["objectID"] } }

    assert_equal %w[ 1 2 3 4 5 6 ], ids.sort
    assert_equal ids.uniq, ids
    assert(fake.queries.all? { it["tags"] == "story,show_hn" })
  end

  test "stops at `after`, exclusive" do
    hits = [ hit(1, 100), hit(2, 200), hit(3, 300) ]
    ids = HnClient.new(get: FakeAlgolia.new(hits), pause: 0).each_page(after: Time.at(100)).flat_map { |page| page.map { it["objectID"] } }
    assert_equal %w[ 3 2 ], ids
  end

  test "reads a real Algolia page" do
    body = file_fixture("algolia/page1.json").read
    pages = HnClient.new(get: ->(_) { body.tap { body = { hits: [] }.to_json } }, pause: 0).each_page.to_a
    assert_equal 1, pages.size
    assert(pages.first.all? { it["title"].start_with?("Show HN") })
  end
end
