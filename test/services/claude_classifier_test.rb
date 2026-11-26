require "test_helper"

class ClaudeClassifierTest < ActiveSupport::TestCase
  # Stands in for Anthropic::Client: client.messages.create records its arguments and returns the next reply.
  class FakeClient
    Block = Struct.new(:type, :text)
    Reply = Struct.new(:content, :stop_reason)

    attr_reader :requests

    def initialize(*replies)
      @replies = Queue.new
      replies.each { @replies << it }
      @requests = Queue.new
    end

    def messages = self

    def create(**params)
      @requests << params
      reply = @replies.pop(true)
      raise reply if reply.is_a?(Exception)
      return reply if reply.is_a?(Reply)
      Reply.new([ Block.new(:thinking, ""), Block.new(:text, reply.is_a?(Hash) ? reply.to_json : reply) ], :end_turn)
    end
  end

  setup do
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    @ri = Place.find_by!(slug: "providence-rhode-island-us")
    @post = Post.create!(hn_id: 1, title: "Show HN: Providence bus tracker", posted_at: Time.current,
                         status: "candidate", candidate_place_ids: [ @ri.id ])
  end

  def classifier(fake) = ClaudeClassifier.new(model: "claude-test", client: fake)

  test "asks for structured JSON at low effort, without sampling settings, and reads the text block" do
    fake = FakeClient.new({ project: "A bus tracker for Providence", place_role: "about", place: 1, local: true, confidence: 0.9 })
    verdict = classifier(fake).classify(@post)

    assert verdict.local
    assert_equal @ri.id, verdict.place_id
    params = fake.requests.pop
    assert_equal "claude-test", params[:model]
    assert_equal LocalClassifier::SYSTEM, params[:system_]
    assert_equal "low", params.dig(:output_config, :effort)
    assert_equal "json_schema", params.dig(:output_config, :format, :type)
    assert_equal false, params.dig(:output_config, :format, :schema, :additionalProperties)
    assert_not params.key?(:temperature)
    assert_includes params[:messages].last[:content], "1. Providence, Rhode Island, United States"
  end

  test "a refusal or a cut-off reply is a BadAnswer" do
    refused = FakeClient::Reply.new([], :refusal)
    assert_raises(LocalClassifier::BadAnswer) { classifier(FakeClient.new(refused)).classify(@post) }
    cut = FakeClient::Reply.new([ FakeClient::Block.new(:text, '{"proj') ], :max_tokens)
    assert_raises(LocalClassifier::BadAnswer) { classifier(FakeClient.new(cut)).classify(@post) }
  end

  test "rate limits, outages and a bad key are Unavailable, so the run stops and posts wait" do
    error = Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages"))
    assert_raises(LocalClassifier::Unavailable) { classifier(FakeClient.new(error)).classify(@post) }
  end

  test "ClassifyJob asks several posts at once and saves every verdict" do
    posts = [ @post ] + (2..5).map do |i|
      Post.create!(hn_id: i, title: "Show HN: Providence thing #{i}", posted_at: i.hours.ago, status: "candidate", candidate_place_ids: [ @ri.id ])
    end
    answers = posts.map { { project: "Something in Providence", place_role: "about", place: 1, local: true, confidence: 0.8 } }

    assert_equal 5, ClassifyJob.perform_now(classifier: classifier(FakeClient.new(*answers)), threads: 3)
    assert posts.map(&:reload).all?(&:status_local?)
    assert_equal [ "claude-test" ], posts.map(&:classifier_model).uniq
  end

  test "the config picks Claude when CLASSIFIER says so" do
    original = Rails.configuration.x.classifier
    Rails.configuration.x.classifier = "claude"
    assert_instance_of ClaudeClassifier, LocalClassifier.default
    Rails.configuration.x.classifier = "ollama"
    assert_instance_of LocalClassifier, LocalClassifier.default
  ensure
    Rails.configuration.x.classifier = original
  end
end
