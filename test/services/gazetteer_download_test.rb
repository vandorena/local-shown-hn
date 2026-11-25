require "test_helper"

class GazetteerDownloadTest < ActiveSupport::TestCase
  setup { @dir = Dir.mktmpdir }
  teardown { FileUtils.rm_rf(@dir) }

  test "is fresh only when every file is there and under a month old" do
    download = GazetteerDownload.new(dir: @dir)
    assert_not download.fresh?

    GazetteerDownload::FILES.each { File.write(File.join(@dir, it), "a\tb\tc\td\n") }
    assert download.fresh?

    old = 40.days.ago.to_time
    File.utime(old, old, File.join(@dir, GazetteerDownload::ADMIN2))
    assert_not download.fresh?
  end

  test "fetch does nothing while the files are fresh" do
    GazetteerDownload::FILES.each { File.write(File.join(@dir, it), "a\tb\tc\td\n") }
    assert_equal [], GazetteerDownload.new(dir: @dir).fetch
  end
end
