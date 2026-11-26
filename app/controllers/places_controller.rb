class PlacesController < ApplicationController
  # Every place with posts, by country and then state.
  def index
    places = Place.with_post_counts(Post.shown)
    @total = places.sum(&:posts_count)
    @countries = places.group_by { it.country_name || it.country_code }
                       .sort_by { |name, ps| [ -ps.sum(&:posts_count), name ] }
  end

  def show
    @place = Place.find_by!(slug: params[:slug])
    @posts = @place.shown_posts.includes(:place).order(posted_at: :desc)
    @place.posts_count = @posts.size
    @county = @place.county
    @nearby = @place.nearby(Place.with_post_counts(Post.shown))
    @map_places = [ @place, *@nearby ]
  end
end
