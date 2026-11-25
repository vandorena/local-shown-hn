namespace :places do
  desc "Download the GeoNames files, unless the copies on disk are under a month old (FORCE=1 to redo)"
  task fetch: :environment do
    fetched = GazetteerDownload.new.fetch(force: ENV["FORCE"] == "1")
    puts fetched.any? ? "places: fetched #{fetched.join(', ')}" : "places: GeoNames files are up to date"
  end

  desc "Build the places table from the GeoNames files on disk"
  task load: :environment do
    puts "places: loaded #{GazetteerLoader.new.load!} places"
  end

  desc "On boot: fetch the GeoNames files when due, and rebuild the places table if they changed or it is empty"
  task refresh: :environment do
    fetched = GazetteerDownload.new.fetch
    if fetched.any? || Place.none?
      puts "places: loaded #{GazetteerLoader.new.load!} places"
    else
      puts "places: #{Place.count} places, GeoNames files up to date"
    end
  end
end
