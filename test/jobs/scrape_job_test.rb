require "test_helper"

class ScrapeJobTest < ActiveJob::TestCase
  class FakeClient
    attr_reader :after

    def initialize(pages) = @pages = pages

    def each_page(after:, &)
      @after = after
      @pages.each(&)
    end
  end

  test "reaches back a week to refresh points, and imports what it finds" do
    page = JSON.parse(file_fixture("algolia/page1.json").read)["hits"]
    client = FakeClient.new([ page ])
    freeze_time do
      ScrapeJob.perform_now(client:)
      assert_equal 7.days.ago, client.after
    end
    assert_equal 3, Post.count
  end

  test "reaches back to the newest post we have when that is older than a week" do
    Post.create!(hn_id: 1, title: "Show HN: old", posted_at: 30.days.ago)
    client = FakeClient.new([])
    ScrapeJob.perform_now(client:)
    assert_in_delta 30.days.ago.to_f, client.after.to_f, 5
  end
end
