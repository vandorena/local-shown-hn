# ADMIN_PASSWORD guards /admin (HTTP basic auth, any user name). Without it the review pages don't exist,
# except in development and test, where the password is "dev".
Rails.application.configure do
  config.x.admin_password = ENV["ADMIN_PASSWORD"].presence || ("dev" if Rails.env.local?)
end
