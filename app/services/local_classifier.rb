# Asks a local model (through Ollama) whether a candidate post is about one of the places PlaceMatcher
# found. The model picks a place by its number in the list, or none, so every location on the site comes
# from GeoNames rather than from the model.
require "net/http"

class LocalClassifier
  class Unavailable < StandardError; end # Ollama is down or the model is missing: try again later
  class BadAnswer < StandardError; end # the model's reply didn't fit the schema

  Verdict = Data.define(:local, :place_id, :confidence, :reason)

  SYSTEM = <<~PROMPT.freeze
    You sort Show HN posts for a site that lists projects tied to a specific city, town, county or metro area.

    A post is LOCAL when the project is for or about one particular place smaller than a country: it serves
    people who live in or visit that place, uses that place's data (transit, zoning, housing, elections,
    restaurants, weather), maps or models it, or is about its government, culture or history.

    A post is NOT local when:
    - the place is only where the maker lives or works ("I built X from Berlin"), or a passing mention;
    - the name means something else: a product, framework, company, person or word (Phoenix framework,
      "Reading list", Zanzibar authorization, Haiku the model);
    - the project covers a whole country, a state or province, or the world;
    - the place in the post is not in the candidate list (then answer place 0).

    Answer with JSON only: {"local": true|false, "place": <number of the candidate, 0 for none>,
    "confidence": <0 to 1, how sure you are of your answer>, "reason": "<one short sentence>"}.
  PROMPT

  SCHEMA = {
    type: "object",
    properties: {
      local: { type: "boolean" },
      place: { type: "integer", minimum: 0, maximum: PlaceMatcher::MAX_CANDIDATES },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      reason: { type: "string" }
    },
    required: %w[ local place confidence reason ]
  }.freeze

  TEXT_LIMIT = 1_500 # characters of the post's text; enough to tell, and keeps a CPU-only server quick

  attr_reader :model

  # post: takes a URI and a JSON body, returns the response body (tests pass a fake).
  def initialize(url: Rails.configuration.x.ollama_url, model: Rails.configuration.x.ollama_model, post: method(:http_post))
    @uri = URI.join(url, "/api/chat")
    @model = model
    @post = post
  end

  def classify(post)
    places = Place.where(id: post.candidate_place_ids).index_by(&:id).values_at(*post.candidate_place_ids).compact
    return Verdict.new(local: false, place_id: nil, confidence: 1.0, reason: "No candidate places.") if places.empty?

    answer = ask(prompt(post, places))
    choice = answer.fetch("place").to_i
    place = places[choice - 1] if choice.between?(1, places.size)
    local = answer.fetch("local") == true && !place.nil?
    Verdict.new(local:, place_id: local ? place.id : nil, confidence: answer.fetch("confidence").to_f.clamp(0.0, 1.0),
                reason: answer.fetch("reason").to_s.truncate(500))
  rescue KeyError, TypeError, JSON::ParserError => e
    raise BadAnswer, e.message
  end

  private

  def prompt(post, places)
    text = post.story_text.present? ? CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(post.story_text)).squish.truncate(TEXT_LIMIT) : "(none)"
    list = places.each_with_index.map do |place, i|
      "#{i + 1}. #{place.label} (#{place.kind}, population #{place.population.to_fs(:delimited)})"
    end
    <<~TEXT
      Title: #{post.title}
      URL: #{post.url.presence || '(none)'}
      Text: #{text}

      Candidate places:
      #{list.join("\n")}
    TEXT
  end

  def ask(user)
    body = {
      model: @model, stream: false, think: false, format: SCHEMA, options: { temperature: 0 },
      messages: [ { role: "system", content: SYSTEM }, { role: "user", content: user } ]
    }
    reply = JSON.parse(@post.call(@uri, body.to_json))
    raise Unavailable, reply["error"] if reply["error"]
    JSON.parse(reply.dig("message", "content").to_s)
  end

  def http_post(uri, json)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 300) do |http|
      response = http.post(uri.path, json, "Content-Type" => "application/json")
      raise Unavailable, "#{response.code}: #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Unavailable, "#{e.class}: #{e.message}"
  end
end
