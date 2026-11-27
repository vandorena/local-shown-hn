# The front page: every post the model is sure is about a place, on a map and in a list.
class PostsController < ApplicationController
  PER_PAGE = 50
  MAP_LIMIT = 200

  def index
    @query = params[:q].to_s.strip.first(100)
    @sort = params[:sort] == "top" ? "top" : "new"
    scope = Post.shown.includes(:place)
    scope = scope.joins(:place).merge(Place.search(@query)) if @query.present?
    @total = scope.count
    ordered = @sort == "top" ? scope.ranked : scope.order(posted_at: :desc)

    # The map shows the first MAP_LIMIT posts of this list unless "show all projects" is ticked.
    @map_all = params[:all] == "1"
    @map_places = Place.with_post_counts(@map_all ? scope : Post.where(id: ordered.limit(MAP_LIMIT).pluck(:id)))

    @page = [ params[:page].to_i, 1 ].max
    @posts = ordered.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def feed
    @posts = Post.shown.includes(:place).order(posted_at: :desc).limit(50)
  end
end
