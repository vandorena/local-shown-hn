require "test_helper"

class LocalClassifierTest < ActiveSupport::TestCase
  # Stands in for Ollama's /api/chat: records requests, answers with `content` (a Hash becomes JSON).
  class FakeOllama
    attr_reader :requests

    def initialize(*contents) = (@contents = contents) && (@requests = [])

    def call(uri, json)
      @requests << [ uri, JSON.parse(json) ]
      content = @contents.shift
      raise content if content.is_a?(Exception)
      { model: "fake", message: { role: "assistant", content: content.is_a?(Hash) ? content.to_json : content }, done: true }.to_json
    end
  end

  setup do
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    @ri = Place.find_by!(slug: "providence-rhode-island-us")
    @ut = Place.find_by!(slug: "providence-utah-us")
    @post = Post.create!(hn_id: 1, title: "Show HN: Providence bus tracker", url: "https://pvdbus.example",
                         story_text: "<p>Live RIPTA arrivals &amp; alerts.", posted_at: Time.current,
                         status: "candidate", candidate_place_ids: [ @ri.id, @ut.id ])
  end

  def classifier(fake) = LocalClassifier.new(url: "http://ollama:11434", model: "test-model", post: fake)

  test "a local verdict needs the model's summary to name the place" do
    answer = { project: "Scoring software for cycling races", place_role: "about", place: 1, local: true, confidence: 0.9 }
    assert_not classifier(FakeOllama.new(answer)).classify(@post).local

    county = Place.find_by!(name: "Providence County")
    @post.update!(candidate_place_ids: [ county.id ])
    answer = { project: "Property records in Providence", place_role: "about", place: 1, local: true, confidence: 0.9 }
    assert classifier(FakeOllama.new(answer)).classify(@post).local
  end

  test "goes with the candidate the summary names when the model picks another number" do
    provo = Place.find_by!(name: "Provo")
    @post.update!(candidate_place_ids: [ @ri.id, provo.id ])
    answer = { project: "Trail maps around Provo", place_role: "about", place: 1, local: true, confidence: 0.9 }
    verdict = classifier(FakeOllama.new(answer)).classify(@post)
    assert verdict.local
    assert_equal provo.id, verdict.place_id
  end

  test "maps the model's numbered choice back to the GeoNames place" do
    fake = FakeOllama.new({ project: "A bus tracker for Providence", place_role: "about", place: 1, local: true, confidence: 0.92 })
    verdict = classifier(fake).classify(@post)

    assert verdict.local
    assert_equal @ri.id, verdict.place_id
    assert_in_delta 0.92, verdict.confidence
    assert_equal "A bus tracker for Providence (place: about)", verdict.reason
    uri, body = fake.requests.first
    assert_equal "http://ollama:11434/api/chat", uri.to_s
    assert_equal "test-model", body["model"]
    assert_equal false, body["stream"]
    assert_equal %w[ project place_role place local confidence ], body.dig("format", "required")
    prompt = body["messages"].last["content"]
    assert_includes prompt, "1. Providence, Rhode Island, United States (city, population 190,934)"
    assert_includes prompt, "2. Providence, Utah, United States"
    assert_includes prompt, "Live RIPTA arrivals & alerts."
  end

  test "local with no valid place counts as not local" do
    verdict = classifier(FakeOllama.new({ project: "x", place_role: "about", place: 7, local: true, confidence: 0.8 })).classify(@post)
    assert_not verdict.local
    assert_nil verdict.place_id
  end

  test "local counts only when the model also says the project is about the place" do
    answer = { project: "A desktop app named Providence", place_role: "name", place: 1, local: true, confidence: 0.9 }
    assert_not classifier(FakeOllama.new(answer)).classify(@post).local
  end

  test "an answer that does not fit the schema is a BadAnswer" do
    assert_raises(LocalClassifier::BadAnswer) { classifier(FakeOllama.new("not json")).classify(@post) }
    assert_raises(LocalClassifier::BadAnswer) { classifier(FakeOllama.new({ local: true })).classify(@post) }
  end

  test "an Ollama error, such as a missing model, is Unavailable" do
    fake = ->(_, _) { { error: "model 'test-model' not found" }.to_json }
    assert_raises(LocalClassifier::Unavailable) { classifier(fake).classify(@post) }
  end

  test "ClassifyJob stores verdicts, retries a bad answer once, and stops when Ollama is down" do
    other = Post.create!(hn_id: 2, title: "Show HN: Providence app", posted_at: 1.hour.ago, status: "candidate", candidate_place_ids: [ @ri.id ])
    third = Post.create!(hn_id: 3, title: "Show HN: Another", posted_at: 2.hours.ago, status: "candidate", candidate_place_ids: [ @ri.id ])
    fake = FakeOllama.new(
      { project: "Transit in Providence", place_role: "about", place: 1, local: true, confidence: 0.9 },
      "garbage", { project: "An app", place_role: "name", place: 0, local: false, confidence: 0.7 },
      LocalClassifier::Unavailable.new("connection refused")
    )

    assert_equal 2, ClassifyJob.perform_now(classifier: classifier(fake))
    assert @post.reload.status_local?
    assert_equal @ri, @post.place
    assert_equal "test-model", @post.classifier_model
    assert other.reload.status_not_local?
    assert third.reload.status_candidate?
    assert_equal [ @post ], Post.shown.to_a
  end

  test "a post the model answers badly twice is set aside" do
    ClassifyJob.perform_now(classifier: classifier(FakeOllama.new("bad", "worse")))
    assert @post.reload.status_not_local?
    assert_match(/unusable/, @post.reason)
  end
end
