# A city, town or county from GeoNames. Countries and states are never places here: the site is about
# things smaller than that. States are kept on each row (admin1_name) to tell same-named places apart.
class Place < ApplicationRecord
  KINDS = %w[ city county ].freeze

  validates :geonames_id, :name, :ascii_name, :slug, :country_code, :lat, :lng, presence: true
  validates :kind, inclusion: { in: KINDS }

  def to_param = slug

  # "Providence, Rhode Island, US"
  def label
    [ name, admin1_name, country_code ].compact_blank.uniq.join(", ")
  end
end
