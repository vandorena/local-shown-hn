require "test_helper"

class GazetteerDownloadTest < ActiveSupport::TestCase
  setup { @dir = Dir.mktmpdir }
  teardown { FileUtils.rm_rf(@dir) }

  test "is fresh only when every file is there and under a month old" do
    download = GazetteerDownload.new(dir: @dir)
    assert_not download.fresh?

    download.files.each { File.write(File.join(@dir, it), "a\tb\tc\td\n") }
    assert download.fresh?

    old = 40.days.ago.to_time
    File.utime(old, old, File.join(@dir, GazetteerDownload::ADMIN2))
    assert_not download.fresh?
  end

  test "fetch does nothing while the files are fresh" do
    download = GazetteerDownload.new(dir: @dir)
    download.files.each { File.write(File.join(@dir, it), "a\tb\tc\td\n") }
    assert_equal [], download.fetch
  end

  test "localities are districts and villages with a known population" do
    row = ->(klass, code, pop) { [ "1", "X", "X", "", "0", "0", klass, code, "GB", "", "ENG", "", "", "", pop.to_s ] }
    assert GazetteerDownload.locality?(row.("A", "ADM3", 146_338))
    assert GazetteerDownload.locality?(row.("P", "PPL", 800))
    assert_not GazetteerDownload.locality?(row.("P", "PPL", 0)) # no population: can't rank it
    assert_not GazetteerDownload.locality?(row.("P", "PPL", 12_000)) # in cities5000.txt already
    assert_not GazetteerDownload.locality?(row.("P", "PPLH", 800)) # historical
    assert_not GazetteerDownload.locality?(row.("H", "STM", 800)) # a river
  end

  test "localities can be switched off" do
    assert_not_includes GazetteerDownload.new(dir: @dir, localities: false).files, GazetteerDownload::LOCALITIES
  end
end
