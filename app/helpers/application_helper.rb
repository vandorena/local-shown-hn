module ApplicationHelper
  def distance(meters)
    return "-" if meters.nil?
    return "#{meters} m" if meters < 1000
    meters < 10_000 ? format("%.1f km", meters / 1000.0) : "#{(meters / 1000.0).round} km"
  end

  def percent(part, whole)
    whole.zero? ? "-" : "#{(100.0 * part / whole).round}%"
  end
end
