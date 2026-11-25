# The review pages, behind HTTP basic auth (config/initializers/admin.rb).
class Admin::BaseController < ApplicationController
  before_action :authenticate

  private

  def authenticate
    password = Rails.configuration.x.admin_password
    raise ActionController::RoutingError, "Not Found" if password.nil?

    authenticate_or_request_with_http_basic("Local Show HN admin") do |_user, given|
      ActiveSupport::SecurityUtils.secure_compare(given, password)
    end
  end
end
