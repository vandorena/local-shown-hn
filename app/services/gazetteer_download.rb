# Keeps the GeoNames files the gazetteer is built from on disk (CC BY 4.0, no account or key; the
# licence asks for a "GeoNames" credit, which is in the footer). Same approach as findme's GeoDatabase:
# download to a .part file, check it, rename it into place, and skip it while it is under a month old.
require "net/http"
require "zip"

class GazetteerDownload
  BASE = "https://download.geonames.org/export/dump/".freeze
  DIR = ENV.fetch("GEONAMES_DIR", Rails.root.join("storage/geonames").to_s)
  CITIES = "cities5000.txt".freeze
  ADMIN1 = "admin1CodesASCII.txt".freeze
  ADMIN2 = "admin2Codes.txt".freeze
  FILES = [ CITIES, ADMIN1, ADMIN2 ].freeze
  MAX_AGE = 32.days

  def self.path(name, dir: DIR) = File.join(dir, name)

  def initialize(dir: DIR, now: Time.now.utc)
    @dir = dir
    @now = now
  end

  def fresh?
    FILES.all? do |name|
      path = self.class.path(name, dir: @dir)
      File.exist?(path) && File.mtime(path) > @now - MAX_AGE
    end
  end

  # Downloads every file unless all are fresh. Returns the names fetched (empty when nothing was due).
  def fetch(force: false)
    return [] if fresh? && !force

    FileUtils.mkdir_p(@dir)
    FILES.each { fetch_one(it) }
  end

  private

  def fetch_one(name)
    target = self.class.path(name, dir: @dir)
    part = "#{target}.part"
    if name == CITIES
      zip = "#{target}.zip.part"
      download(URI.join(BASE, "cities5000.zip"), zip)
      Zip::File.open(zip) { |archive| archive.get_entry(CITIES).extract(File.basename(part), destination_directory: @dir) { true } }
    else
      download(URI.join(BASE, name), part)
    end
    check!(part)
    File.utime(@now, @now, part) # an extracted file keeps the zip's timestamp; freshness means when we fetched it
    File.rename(part, target)
  ensure
    FileUtils.rm_f([ part, zip ].compact)
  end

  # Refuses an empty or truncated file: every line of these files is tab-separated, with at least 4 fields.
  def check!(part)
    lines = File.foreach(part).first(50)
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
