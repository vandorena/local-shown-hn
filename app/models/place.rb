# A city, town, village, district, county or small state from GeoNames. Countries and big states are never places here: the
# site is about things smaller than that. Each row keeps its state (admin1_name) to tell same-named places
# apart.
class Place < ApplicationRecord
  KINDS = %w[ city district county state ].freeze
  # Words that wrap a district or county's own name: "Cherwell District", "Borough of Wokingham".
  AREA_WORDS = /\A(?:(?:london |metropolitan |royal )?borough|district|city|county|municipality) of |
                \s(?:district|borough|township|municipality|county|parish|province|prefecture)\z/ix
  NEARBY_KM = 120

  has_many :posts, dependent: :nullify

  attribute :posts_count, :integer, default: 0 # filled in by with_post_counts; not a column

  validates :geonames_id, :name, :ascii_name, :slug, :country_code, :lat, :lng, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :search, lambda { |query|
    like = "%#{sanitize_sql_like(query)}%"
    where("places.name LIKE :q OR places.ascii_name LIKE :q OR places.admin1_name LIKE :q OR places.country_name LIKE :q", q: like)
  }

  # The places the given posts are about, each with posts_count set.
  def self.with_post_counts(posts)
    counts = posts.unscope(:includes, :order, :limit, :offset).where.not(place_id: nil).group(:place_id).count
    where(id: counts.keys).to_a.each { it.posts_count = counts[it.id] }
  end

  def to_param = slug

  # "Cherwell District" -> "Cherwell"; a name without such words stays as it is.
  def self.short_name(name) = name.to_s.gsub(AREA_WORDS, "").strip.presence || name

  def county? = kind == "county"
  def district? = kind == "district"
  def state? = kind == "state"
  def town? = kind == "city"

  # "Providence, Rhode Island, United States"
  def label
    [ name, admin1_name, country_name || country_code ].compact_blank.uniq.join(", ")
  end

  # "Rhode Island, United States"
  def region
    [ admin1_name, country_name || country_code ].compact_blank.uniq.join(", ")
  end

  # The county a town is in, when GeoNames has one with towns big enough to make the list.
  def county
    return nil unless (town? || district?) && admin2.present?
    Place.find_by(kind: "county", country_code:, admin1:, admin2:)
  end

  # The district a town or village is in, when GeoNames has one.
  def district
    return nil unless town? && admin3.present?
    Place.find_by(kind: "district", country_code:, admin1:, admin2:, admin3:)
  end

  # The small state a town or county is in, when it is on the list.
  def state
    return nil if state? || admin1.blank?
    Place.find_by(kind: "state", country_code:, admin1:)
  end

  # The posts shown for this place. A district's include those about its villages, a county's those about
  # its towns, and a state's those about everything in it.
  def shown_posts
    case kind
    when "district" then Post.shown.where(place_id: Place.where(country_code:, admin1:, admin2:, admin3:).select(:id))
    when "county" then Post.shown.where(place_id: Place.where(country_code:, admin1:, admin2:).select(:id))
    when "state" then Post.shown.where(place_id: Place.where(country_code:, admin1:).select(:id))
    else Post.shown.where(place: self)
    end
  end

  # Up to `limit` of `places` within NEARBY_KM, nearest first.
  def nearby(places, limit: 8)
    places.reject { it.id == id }.map { [ it, distance_to(it) ] }.select { |_, km| km <= NEARBY_KM }
          .sort_by(&:last).first(limit).map(&:first)
  end

  # Great-circle distance in km.
  def distance_to(other)
    rad = Math::PI / 180
    dlat = (other.lat - lat) * rad
    dlng = (other.lng - lng) * rad
    a = Math.sin(dlat / 2)**2 + Math.cos(lat * rad) * Math.cos(other.lat * rad) * Math.sin(dlng / 2)**2
    6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  # What the map needs: [lat, lng, name, url, count].
  def map_point(url) = [ lat.round(4), lng.round(4), label, url, posts_count ]
end
