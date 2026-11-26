# A city, town or county from GeoNames. Countries and states are never places here: the site is about
# things smaller than that. States are kept on each row (admin1_name) to tell same-named places apart.
class Place < ApplicationRecord
  KINDS = %w[ city county ].freeze
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

  def county? = kind == "county"

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
    return nil if county? || admin2.blank?
    Place.find_by(kind: "county", country_code:, admin1:, admin2:)
  end

  # The posts shown for this place. A county's include those about its towns.
  def shown_posts
    return Post.shown.where(place: self) unless county?
    Post.shown.where(place_id: Place.where(country_code:, admin1:, admin2:).select(:id))
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
end
