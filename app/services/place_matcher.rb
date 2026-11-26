# Finds the towns and counties a Show HN post might be about, cheaply, so only those posts go to the
# local model. It only finds candidates; LocalClassifier decides.
#
# A name matches when its words appear capitalised in the title or text, or anywhere in the URL. In a
# hostname it may also start or end a run-together word (melbournetrams, isoburlington, newyorkbikes), but
# only for big places and only with a local cue word.
#   - Strong names count on their own: names of two or more words ("Salt Lake City"), and one-word names of
#     places with 100,000+ people that are not ordinary words ("Seattle", "Lagos").
#   - Weak names need more: a qualifier right after them ("Reading, PA", "Faro, Portugal"), or a local cue
#     word somewhere in the post (bus, council, residents...) as long as the name does not just start a
#     sentence ("Most people..."). Weak means one-word names of smaller places, and words in
#     config/gazetteer/common_words.txt (Reading, Mobile, Providence).
#   - Tech words (config/gazetteer/tech_words.txt: Phoenix, Ruby, Haiku) and names of three letters or
#     fewer count only with a qualifier.
#   - So do names that are also a state, province or country (Vermont, Georgia, Victoria): "Vermont" means
#     the state, not the Melbourne suburb. A place in a region of its own name still counts (Singapore,
#     Tokyo), and so does a city of BIG_CITY people (San Jose, though Costa Rica has a province of that name).
#   - Minor places, villages under 5,000 people and districts, are strictest: nearly every word is a village
#     somewhere ("Research", Victoria; "Index", Washington). They count with a qualifier, or else only as
#     one word in the title or URL, with a local cue, and not an ordinary word.
class PlaceMatcher
  MAX_WORDS = 4
  MAX_CANDIDATES = 5
  HOST_MIN = 5 # shortest name found inside a run-together hostname word; shorter ones are mostly noise
  # Only big, unambiguous places are looked for inside hostname words (see strong?): smaller names turn up
  # inside ordinary words and people's names far too often (salemove, austinkpickett).
  STRONG_POPULATION = 100_000
  BIG_CITY = 500_000 # big enough that its name means the city, even where a region shares it (San Jose, Sofia)
  SOURCE_BONUS = { title: 3.0, url: 1.5, text: 0.0 }.freeze
  # Words that suggest a post is about a place. Kept to ones HN rarely uses otherwise: no "local"
  # (local-first), "library", "property", "train" or "events".
  LOCAL_CUES = %w[
    city cities county counties town towns township village borough parish municipal municipality
    council councils mayor residents neighborhood neighborhoods neighbourhood neighbourhoods downtown
    transit bus buses subway tram trams commute commuters parking traffic zoning potholes permits
    restaurants beaches trails hiking ferry ferries landlords housing elections voters nearby
  ].to_set.freeze
  ALIASES = {
    "nyc" => "new york city", "new york" => "new york city", "philly" => "philadelphia",
    "nola" => "new orleans", "sf" => "san francisco"
  }.freeze

  Token = Data.define(:norm, :capitalized, :upcase, :initial)
  # Where a place is: its state and country names (regions), what may follow its name to pin it down
  # (qualifiers: "rhode island", "usa"), and 2-letter codes that count only in capitals (codes: "ri", "us").
  Area = Data.define(:regions, :qualifiers, :codes)
  Hit = Data.define(:place_id, :score)

  class << self
    # Lowercase ASCII words joined by single spaces: "São Paulo" -> "sao paulo", "Wilkes-Barre" -> "wilkes barre".
    def normalize(text)
      ActiveSupport::Inflector.transliterate(text.to_s, "").downcase.gsub(/['’]/, "").gsub(/[^a-z0-9]+/, " ").strip
    end

    def word_list(name)
      Rails.root.join("config/gazetteer", name).readlines(chomp: true).reject { it.blank? || it.start_with?("#") }.to_set
    end

    def instance = @instance ||= new
    def reset! = @instance = nil
  end

  def initialize(places: Place.all, common: self.class.word_list("common_words.txt"), tech: self.class.word_list("tech_words.txt"))
    @common = common
    @tech = tech
    build_index(places)
  end

  # Returns up to MAX_CANDIDATES place ids, most likely first; empty when nothing matched.
  def candidates(title:, text: nil, url: nil)
    sources = { title: tokens(title.to_s.sub(/\A(?:Show HN:\s*)+/i, "")), text: tokens(plain(text)), url: url_tokens(url, split: true) }
    cue = sources.values.flatten.any? { LOCAL_CUES.include?(it.norm) }
    # A name inside a hostname word is weak evidence (bananaide, temperature), so it needs a cue too.
    sources[:url] = url_tokens(url, split: false) unless cue
    hits = sources.flat_map { |source, toks| scan(toks, source, cue) }
    hits.group_by(&:place_id).map { |id, hs| [ id, hs.sum(&:score) ] }
        .sort_by { |_, score| -score }.first(MAX_CANDIDATES).map(&:first)
  end

  private

  def build_index(places)
    @names = Hash.new { |h, k| h[k] = [] } # normalized name => [place rows]
    # place id => its Area. Places in the same state share one, which keeps 500k+ places small in memory.
    @areas = {}
    shared = Hash.new { |h, (a1, a1_name, cc, c_name)| h[[ a1, a1_name, cc, c_name ]] = area(a1, a1_name, cc, c_name) }
    @population = {}
    @regions = Set.new # normalized state, province and country names
    @biggest = Hash.new(0) # normalized name => population of the biggest town (not minor place) with that name
    @biggest_minor = Hash.new(0) # the same, for minor places
    @minor = Set.new # ids of villages and districts
    @squashed = {} # "newyorkcity" => "new york city", for names run together in a hostname
    columns = %i[ id name ascii_name population admin1 admin1_name country_code country_name kind ]
    each_place_row(places, columns) do |id, name, ascii, pop, a1, a1_name, cc, c_name, kind|
      @population[id] = pop
      minor = kind == "district" || (kind == "city" && pop < GazetteerDownload::VILLAGE_MAX)
      @minor << id if minor
      names = [ name, ascii ]
      names += names.map { Place.short_name(it) } if kind == "district" # "Cherwell District" is "Cherwell" in a post
      names.map { self.class.normalize(it) }.uniq.each do |key|
        next if key.length < 3 || key.count(" ") >= MAX_WORDS || LOCAL_CUES.include?(key)
        @names[key] << id
        biggest = minor ? @biggest_minor : @biggest
        biggest[key] = [ biggest[key], pop ].max
      end
      @areas[id] = shared[[ a1, a1_name, cc, c_name ]]
      @regions.merge(@areas[id].regions)
    end
    ALIASES.each do |short, long|
      next unless @names.key?(long)
      @names[short] = @names[long]
      @biggest[short] = @biggest[long]
    end
    @names.each_key do |key|
      squashed = key.delete(" ")
      next if squashed.length < HOST_MIN || !host_name?(key) || @tech.include?(key) || @regions.include?(key)
      size = [ @biggest[key], @biggest_minor[key] ].max
      @squashed[squashed] = key if size > [ @biggest[@squashed[squashed]], @biggest_minor[@squashed[squashed]] ].max
    end
    @squashed["nyc"] = "nyc"
  end

  # Reads the places a batch at a time: plucking 500k+ rows in one go holds them all in memory at once.
  def each_place_row(places, columns, &)
    places.in_batches(of: 20_000) { |batch| batch.pluck(*columns).each(&) }
  end

  def area(a1, a1_name, cc, c_name)
    regions = [ a1_name, c_name ].compact.map { self.class.normalize(it) }.to_set
    qualifiers = regions.dup
    qualifiers << "usa" if cc == "US"
    codes = [ cc.downcase, (a1.downcase if a1.to_s.match?(/\A[A-Z]{2}\z/)), ("us" if cc == "US"), ("uk" if cc == "GB") ].compact.to_set
    Area.new(regions: regions.freeze, qualifiers: qualifiers.freeze, codes: codes.freeze)
  end

  # Longest match first, left to right: "New York City" is one match, not also "New York" and "York".
  def scan(toks, source, cue)
    hits = []
    i = 0
    while i < toks.size
      n = MAX_WORDS.downto(1).find { |len| match?(toks, i, len, source) }
      if n
        key = toks[i, n].map(&:norm).join(" ")
        hits.concat(score(@names[key], key, n, toks[i + n, 3] || [], source, cue, initial: toks[i].initial))
      end
      i += n || 1
    end
    hits
  end

  def match?(toks, i, len, source)
    words = toks[i, len]
    return false if words.size < len

    key = words.map(&:norm).join(" ")
    @names.key?(key) && (source == :url || words.first.capitalized || ALIASES.key?(key))
  end

  def score(ids, key, n, rest, source, cue, initial:)
    qualified = ids.select { qualified?(it, rest) }
    ids = ids.select { @areas[it].regions.include?(key) || @population[it] >= BIG_CITY } if @regions.include?(key) && !ALIASES.key?(key)
    minor, towns = ids.partition { @minor.include?(it) }
    allowed =
      if qualified.any? then qualified
      else allowed_towns(towns, key, n, source, cue, initial) + allowed_minor(minor, key, n, source, cue)
      end
    allowed.map do |id|
      bonus = SOURCE_BONUS[source] + (qualified.include?(id) ? 4 : 0) + (cue ? 1 : 0) + n
      Hit.new(place_id: id, score: Math.log10(@population[id] + 10) + bonus)
    end
  end

  def allowed_towns(ids, key, n, source, cue, initial)
    if ids.empty? || qualifier_only?(key, n) then []
    elsif strong?(key, n) then ids
    elsif cue && !(source == :text && initial) then ids
    else []
    end
  end

  def allowed_minor(ids, key, n, source, cue)
    return [] if ids.empty? || n > 1 || !cue || source == :text || qualifier_only?(key, n) || @common.include?(key)
    ids
  end

  # Names looked for inside hostname words: big towns, and big districts (Cherwell), never ordinary words.
  def host_name?(key)
    strong?(key, key.count(" ") + 1) || (!key.include?(" ") && @biggest_minor[key] >= STRONG_POPULATION && !@common.include?(key))
  end

  def strong?(key, n) = n > 1 || ALIASES.key?(key) || (@biggest[key] >= STRONG_POPULATION && !@common.include?(key))

  def qualifier_only?(key, n) = n == 1 && !ALIASES.key?(key) && (@tech.include?(key) || key.length <= 3)

  def qualified?(id, rest)
    return false if rest.empty?
    phrases = (1..rest.size).map { |k| rest.first(k).map(&:norm).join(" ") }
    area = @areas[id]
    phrases.any? { area.qualifiers.include?(it) } || (rest.first.upcase && area.codes.include?(rest.first.norm))
  end

  # Words, each marked with whether it starts a sentence (or the text), where capitals prove nothing.
  def tokens(text)
    initial = true
    text.to_s.scan(/([[:alnum:]]+(?:['’][[:alpha:]]+)?)|([.!?:;\n]+)/).filter_map do |word, stop|
      if stop
        initial = true
        next
      end
      token = Token.new(norm: self.class.normalize(word), capitalized: word.match?(/\A[[:upper:]]/),
                        upcase: word.match?(/\A[[:upper:]]{2,}\z/), initial:)
      initial = false
      token unless token.norm.empty?
    end
  end

  # Host and path words, lowercase: "providence-bus.org/routes" -> providence, bus, routes. With split,
  # host words that run a place name together with other words are split: "provobus" -> provo, bus.
  def url_tokens(url, split:)
    return [] if url.blank?
    uri = URI.parse(url)
    skip = %w[ www com org net io app dev github gitlab html ]
    host = uri.host.to_s.downcase.split(/[^[:alnum:]]+/).reject { skip.include?(it) }.flat_map { split ? split_host_word(it) : [ it ] }
    path = uri.path.to_s.split(/[^[:alnum:]]+/).reject { skip.include?(it.downcase) }.map { self.class.normalize(it) }
    (host + path).reject(&:empty?).flat_map(&:split)
                 .map { Token.new(norm: it, capitalized: false, upcase: false, initial: false) }
  rescue URI::InvalidURIError
    []
  end

  # "isoburlington" -> ["iso", "burlington"]; a word that is already a name, or holds none, stays whole.
  def split_host_word(word)
    return [ word ] if @names.key?(word) || word.length < HOST_MIN + 2

    (word.length - 2).downto(HOST_MIN) do |len|
      if (key = @squashed[word[0, len]]) then return [ key, word[len..] ] end
      if (key = @squashed[word[-len..]]) then return [ word[0...-len], key ] end
    end
    [ word ]
  end

  def plain(html)
    return "" if html.blank?
    CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(html.gsub(/<p>/i, "\n<p>")))
  end
end
