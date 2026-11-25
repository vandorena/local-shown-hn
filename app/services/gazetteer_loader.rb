# Builds the places table from the GeoNames files GazetteerDownload keeps on disk.
#
# Cities and towns come from cities5000.txt (5,000+ people). Counties come from admin2Codes.txt, which has
# no coordinates, so a county sits at the population-weighted centre of its towns; a county with no town
# of 5,000 is left out. Historical and abandoned places (PPLH, PPLQ, PPLW) are dropped.
class GazetteerLoader
  SKIPPED_FEATURES = %w[ PPLH PPLQ PPLW PPLCH ].freeze
  BATCH = 2_000

  def initialize(dir: GazetteerDownload::DIR)
    @dir = dir
  end

  # Upserts every place and returns how many rows were written.
  def load!
    admin1 = read_admin1
    cities = read_cities(admin1)
    counties = read_counties(admin1, cities)
    rows = with_unique_slugs(cities + counties)
    now = Time.current
    rows.each_slice(BATCH) do |batch|
      Place.upsert_all(batch.map { it.merge(created_at: now, updated_at: now) }, unique_by: :geonames_id,
                       update_only: %i[ name ascii_name kind country_code admin1 admin1_name admin2 lat lng population slug ])
    end
    rows.size
  end

  private

  def file(name) = GazetteerDownload.path(name, dir: @dir)

  def each_row(name, &)
    File.foreach(file(name), chomp: true) { |line| yield line.split("\t", -1) }
  end

  # "US.RI" => "Rhode Island"
  def read_admin1
    {}.tap { |names| each_row(GazetteerDownload::ADMIN1) { |code, name, ascii| names[code] = ascii.presence || name } }
  end

  def read_cities(admin1)
    rows = []
    each_row(GazetteerDownload::CITIES) do |f|
      next if SKIPPED_FEATURES.include?(f[7])
      country, a1, a2 = f[8], f[10], f[11]
      rows << {
        geonames_id: f[0].to_i, name: f[1], ascii_name: f[2].presence || f[1], kind: "city",
        country_code: country, admin1: a1.presence, admin1_name: admin1["#{country}.#{a1}"],
        admin2: a2.presence, lat: f[4].to_f, lng: f[5].to_f, population: f[14].to_i
      }
    end
    rows
  end

  def read_counties(admin1, cities)
    towns = cities.select { it[:admin2] }.group_by { [ it[:country_code], it[:admin1], it[:admin2] ] }
    rows = []
    each_row(GazetteerDownload::ADMIN2) do |code, name, ascii, geonames_id|
      country, a1, a2 = code.split(".", 3)
      members = towns[[ country, a1, a2 ]]
      next if members.blank? || geonames_id.blank?

      weights = members.map { [ it[:population], 1 ].max }
      total = weights.sum.to_f
      rows << {
        geonames_id: geonames_id.to_i, name:, ascii_name: ascii.presence || name, kind: "county",
        country_code: country, admin1: a1, admin1_name: admin1["#{country}.#{a1}"], admin2: a2,
        lat: members.zip(weights).sum { |m, w| m[:lat] * w } / total,
        lng: members.zip(weights).sum { |m, w| m[:lng] * w } / total,
        population: members.sum { it[:population] }
      }
    end
    rows
  end

  # "providence-rhode-island-us"; when two places share that, the smaller ones get their GeoNames id appended.
  def with_unique_slugs(rows)
    rows.group_by { slug_for(it) }.flat_map do |slug, same|
      same.sort_by { -it[:population] }.each_with_index.map do |row, i|
        row.merge(slug: i.zero? ? slug : "#{slug}-#{row[:geonames_id]}")
      end
    end
  end

  def slug_for(row)
    [ row[:ascii_name], row[:admin1_name], row[:country_code] ].compact_blank.join(" ").parameterize.presence ||
      "place-#{row[:geonames_id]}"
  end
end
