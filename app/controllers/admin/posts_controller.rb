# Review what the model decided and correct it. Every correction is marked manual, so later scrapes and
# reclassification leave it alone; "Reset" hands a post back to the pipeline.
class Admin::PostsController < Admin::BaseController
  PER_PAGE = 50
  TABS = {
    "shown" => -> { Post.shown },
    "unsure" => -> { Post.status_local.where(manual: false).where(confidence: ...Rails.configuration.x.local_threshold) },
    "rejected" => -> { Post.status_not_local.where(manual: false).where.not(classified_at: nil) },
    "waiting" => -> { Post.status_candidate },
    "hidden" => -> { Post.status_hidden },
    "manual" => -> { Post.where(manual: true) }
  }.freeze

  def index
    @tab = TABS.key?(params[:tab]) ? params[:tab] : "shown"
    @counts = TABS.transform_values { it.call.count }
    @page = [ params[:page].to_i, 1 ].max
    @posts = TABS[@tab].call.includes(:place).order(posted_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @candidates = Place.where(id: @posts.flat_map(&:candidate_place_ids)).index_by(&:id)
  end

  def update
    post = Post.find(params[:id])
    case params[:verdict]
    when "local"
      place = Place.find(params[:place_id])
      post.update!(status: "local", place:, confidence: 1.0, manual: true, reason: "Set by hand.")
    when "not_local" then post.update!(status: "not_local", place: nil, manual: true, reason: "Set by hand.")
    when "hidden" then post.update!(status: "hidden", manual: true)
    when "reset"
      post.update!(status: "new", place: nil, confidence: nil, reason: nil, classified_at: nil, manual: false)
      MatchJob.perform_later
    else return head(:unprocessable_entity)
    end
    redirect_back_or_to admin_posts_path, notice: "#{post.short_title.truncate(50)}: #{params[:verdict].humanize.downcase}."
  end
end
