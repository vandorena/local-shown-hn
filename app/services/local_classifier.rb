# Asks a local model (through Ollama) whether a candidate post is about one of the places PlaceMatcher
# found. The model picks a place by its number in the list, or none, so every location on the site comes
# from GeoNames rather than from the model.
require "net/http"

class LocalClassifier
  class Unavailable < StandardError; end # Ollama is down or the model is missing: try again later
  class BadAnswer < StandardError; end # the model's reply didn't fit the schema

  Verdict = Data.define(:local, :place_id, :confidence, :reason)

  SYSTEM = <<~PROMPT.freeze
    You sort Show HN posts for a site that lists projects tied to one specific city, town, county, metro area or small state.

    The candidate places were found by matching words, so most of them are coincidences: an app named
    after a city, a maker who mentions where they live, a word that happens to be a town. Most posts you
    see are NOT local. Say local only when the post itself shows the project is about that place.

    The test: is the project mainly for, or about, people and things in that one place? A local project
    serves people who live in or visit it (classes, alerts, bookings, guides there), uses its data (transit,
    zoning, housing, elections, restaurants, trash, ferries), maps, models or draws it, is a game or story
    set in it, or is about its government, culture or history. It would mean little to someone with no
    interest in the place.

    Not local:
    - the project shares a name with the place ("Trieste – a desktop app", "Vigo – config management");
    - the place is only where the maker lives, works or got the idea ("I moved to Barcelona and built a
      language app", "a startup from Toronto");
    - the project works the same anywhere: job search, travel booking, finance, databases, dev tools;
    - it covers a whole country, a big state or province that is not in the list, or the world;
    - the place it is about is not in the list: answer place 0.

    Examples:
    - "Live arrivals for every bus in Lisbon" with Lisbon listed: local, Lisbon.
    - "Isometric pixel-art map of my town, Burlington" with Burlington, Ontario listed: local.
    - "A driving game through the streets of Lyon" with Lyon listed: local, Lyon.
    - "Book kids' swim classes in Nairobi" with Nairobi listed: local, Nairobi.
    - "Craoli – find jobs without bias", text says the team is in Zürich: not local.
    - "Budget Friendly City Discovery" with Friendly, Maryland listed: not local, place 0.

    Fill the fields in order. "project": what the project does, in a few words, naming the place if the
    project is about one. "place_role": how the post
    uses the place name: "about" (the project is about, set in or for that place), "name" (only borrowed as
    a product name or another word; the project has nothing to do with the place), "maker"
    (where the maker is), "mention" (in passing) or "none". Then "place", "local" and "confidence" (0 to 1;
    below 0.6 when the post only hints at the place).
  PROMPT

  # Properties are generated in this order, so the model describes the project before it decides.
  SCHEMA = {
    type: "object",
    properties: {
      project: { type: "string" },
      place_role: { type: "string", enum: %w[ about name maker mention none ] },
      place: { type: "integer", minimum: 0, maximum: PlaceMatcher::MAX_CANDIDATES },
      local: { type: "boolean" },
      confidence: { type: "number", minimum: 0, maximum: 1 }
    },
    required: %w[ project place_role place local confidence ]
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
    role = answer.fetch("place_role").to_s
    project = answer.fetch("project").to_s.squish
    # "about" is the model's own test for local; trust a verdict only when the two agree, and only when its
    # summary of the project names the place. When the town is just where the maker lives, it doesn't.
    # The model sometimes picks the wrong number but names the right place ("Bay Area" -> Oakland, then
    # "San Francisco Bay Area" in its summary); go with the place it names.
    place = places.find { names?(project, it) } unless place && names?(project, place)
    local = answer.fetch("local") == true && role == "about" && !place.nil?
    Verdict.new(local:, place_id: local ? place.id : nil, confidence: answer.fetch("confidence").to_f.clamp(0.0, 1.0),
                reason: "#{project} (place: #{role})".truncate(500))
  rescue KeyError, TypeError, JSON::ParserError => e
    raise BadAnswer, e.message
  end

  private

  # Whether text names the place: "Providence", "NYC" for New York City, "Providence" for Providence County.
  def names?(text, place)
    words = " #{PlaceMatcher.normalize(text)} ".gsub(" new york times ", " ")
    names = [ place.name, place.ascii_name ].compact.map { PlaceMatcher.normalize(it) }
    names += names.map { PlaceMatcher.normalize(Place.short_name(it)) } unless place.town?
    names += PlaceMatcher::ALIASES.filter_map { |short, long| short if names.include?(long) }
    names.uniq.reject(&:empty?).any? { words.include?(" #{it} ") }
  end

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
