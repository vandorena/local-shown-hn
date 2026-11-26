# The front page: every post the model is sure is about a place, as a list.
class PostsController < ApplicationController
  PER_PAGE = 50

  def index
    @query = params[:q].to_s.strip.first(100)
    @sort = params[:sort] == "top" ? "top" : "new"
    scope = Post.shown.includes(:place)
    scope = scope.joins(:place).merge(Place.search(@query)) if @query.present?
    @total = scope.count
    @page = [ params[:page].to_i, 1 ].max
    @posts = scope.order(@sort == "top" ? { points: :desc } : { posted_at: :desc })
                  .offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def feed
    @posts = Post.shown.includes(:place).order(posted_at: :desc).limit(50)
  end
end
