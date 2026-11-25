require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    GazetteerLoader.new(dir: Rails.root.join("test/fixtures/files/geonames").to_s).load!
    @ri = Place.find_by!(slug: "providence-rhode-island-us")
    @ut = Place.find_by!(slug: "providence-utah-us")
    @post = Post.create!(hn_id: 1, title: "Show HN: Providence trail map", posted_at: 1.day.ago, status: "local",
                         place: @ri, confidence: 0.7, candidate_place_ids: [ @ri.id, @ut.id ], classified_at: 1.hour.ago)
  end

  def auth(password = "dev") = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", password) }

  test "asks for the password" do
    get admin_posts_path
    assert_response :unauthorized
    get admin_posts_path, headers: auth("wrong")
    assert_response :unauthorized
  end

  test "is switched off when no password is set" do
    Rails.configuration.x.admin_password = nil
    get admin_posts_path, headers: auth
    assert_response :not_found
  ensure
    Rails.configuration.x.admin_password = "dev"
  end

  test "lists the queue with a button per candidate place" do
    get admin_posts_path, headers: auth
    assert_response :success
    assert_select ".post-title a", "Providence trail map"
    assert_select "button", "Local: Providence, Utah, United States"
  end

  test "picking the right place sticks, and Reset hands the post back" do
    patch admin_post_path(@post), params: { verdict: "local", place_id: @ut.id }, headers: auth
    assert_redirected_to admin_posts_path
    @post.reload
    assert_equal @ut, @post.place
    assert @post.manual?
    assert_includes Post.shown, @post

    patch admin_post_path(@post), params: { verdict: "hidden" }, headers: auth
    assert @post.reload.status_hidden?
    assert_not_includes Post.shown, @post

    assert_enqueued_with(job: MatchJob) { patch admin_post_path(@post), params: { verdict: "reset" }, headers: auth }
    @post.reload
    assert @post.status_new?
    assert_not @post.manual?
  end
end
