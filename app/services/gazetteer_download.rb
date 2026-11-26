# Keeps the GeoNames files the gazetteer is built from on disk (CC BY 4.0, no account or key; the
# licence asks for a "GeoNames" credit, which is in the footer). Same approach as findme's GeoDatabase:
# download to a .part file, check it, rename it into place, and skip it while it is under a month old.
#
# localities.txt is cut from the full world dump (allCountries.zip, ~420 MB): districts (ADM3, like
# Cherwell) and villages under 5,000 people, each only with a known population. The dump is streamed
# through once and deleted. GEONAMES_LOCALITIES=0 skips it, for a small server.
require "net/http"
require "zip"

class GazetteerDownload
  BASE = "https://download.geonames.org/export/dump/".freeze
  DIR = ENV.fetch("GEONAMES_DIR", Rails.root.join("storage/geonames").to_s)
  CITIES = "cities5000.txt".freeze
  ADMIN1 = "admin1CodesASCII.txt".freeze
  ADMIN2 = "admin2Codes.txt".freeze
  COUNTRIES = "countryInfo.txt".freeze
  LOCALITIES = "localities.txt".freeze
  VILLAGE_MAX = 5_000 # cities5000.txt has the places from here up
  MAX_AGE = 32.days

  def self.path(name, dir: DIR) = File.join(dir, name)

  def self.localities? = ENV.fetch("GEONAMES_LOCALITIES", "1") == "1"

  # A row of allCountries.txt worth keeping: a district or a village, with people in it.
  def self.locality?(fields)
    population = fields[14].to_i
    return false unless population.positive?

    (fields[6] == "A" && fields[7] == "ADM3") ||
      (fields[6] == "P" && fields[7].start_with?("PPL") && !GazetteerLoader::SKIPPED_FEATURES.include?(fields[7]) && population < VILLAGE_MAX)
  end

  attr_reader :files

  def initialize(dir: DIR, now: Time.now.utc, localities: self.class.localities?)
    @dir = dir
    @now = now
    @files = [ CITIES, ADMIN1, ADMIN2, COUNTRIES, (LOCALITIES if localities) ].compact
  end

  def fresh?
    files.all? do |name|
      path = self.class.path(name, dir: @dir)
      File.exist?(path) && File.mtime(path) > @now - MAX_AGE
    end
  end

  # Downloads every file unless all are fresh. Returns the names fetched (empty when nothing was due).
  def fetch(force: false)
    return [] if fresh? && !force

    FileUtils.mkdir_p(@dir)
    files.each { fetch_one(it) }
  end

  private

  def fetch_one(name)
    target = self.class.path(name, dir: @dir)
    part = "#{target}.part"
    zip = "#{target}.zip.part"
    case name
    when CITIES
      download(URI.join(BASE, "cities5000.zip"), zip)
      Zip::File.open(zip) { |archive| archive.get_entry(CITIES).extract(File.basename(part), destination_directory: @dir) { true } }
    when LOCALITIES
      download(URI.join(BASE, "allCountries.zip"), zip)
      cut_localities(zip, part)
    else
      download(URI.join(BASE, name), part)
    end
    check!(part)
    File.utime(@now, @now, part) # an extracted file keeps the zip's timestamp; freshness means when we fetched it
    File.rename(part, target)
  ensure
    FileUtils.rm_f([ part, zip ].compact)
  end

  def cut_localities(zip, part)
    Zip::File.open(zip) do |archive|
      archive.get_entry("allCountries.txt").get_input_stream do |input|
        File.open(part, "wb") do |out| # the zip hands back raw bytes; the file is UTF-8 either way
          while (line = input.gets)
            out.write(line) if self.class.locality?(line.split("\t", 16))
          end
        end
      end
    end
  end

  # Refuses an empty or truncated file: every line of these files is tab-separated, with at least 4 fields
  # (countryInfo.txt opens with # comments).
  def check!(part)
    lines = File.foreach(part).reject { it.start_with?("#") }.first(50)
    raise "#{File.basename(part)}: empty download" if lines.empty?
    raise "#{File.basename(part)}: not a GeoNames file" unless lines.all? { it.count("\t") >= 3 }
  end

  def download(uri, to)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 120) do |http|
      http.request_get(uri.request_uri) do |response|
        response.value
        File.open(to, "wb") { |out| response.read_body { out.write(it) } }
      end
    end
  end
end
