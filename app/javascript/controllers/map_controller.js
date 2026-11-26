// A Leaflet map of places with local posts: one circle per place, sized by how many posts it has.
// points: [[lat, lng, label, url, count], ...]. focus: [lat, lng] to centre on (a place page).
import { Controller } from "@hotwired/stimulus"
import * as L from "leaflet"

export default class extends Controller {
  static values = { points: Array, focus: Array }

  connect() {
    this.map = L.map(this.element, { worldCopyJump: true, scrollWheelZoom: false })
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18,
      className: "osm-tiles",
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)

    // Scroll zooms the map only once it has been clicked, so the page still scrolls past it.
    this.map.once("focus", () => this.map.scrollWheelZoom.enable())

    const color = getComputedStyle(this.element).getPropertyValue("--accent").trim() || "#ff6600"
    const markers = this.pointsValue.map(([lat, lng, label, url, count]) => {
      const marker = L.circleMarker([lat, lng], {
        radius: Math.min(5 + Math.sqrt(count) * 3, 24),
        color, weight: 1.5, fillColor: color, fillOpacity: 0.45
      })
      const link = document.createElement("a")
      link.href = url
      link.textContent = label
      const popup = document.createElement("div")
      popup.append(link, document.createElement("br"), `${count} post${count === 1 ? "" : "s"}`)
      return marker.bindPopup(popup).bindTooltip(label)
    })
    const layer = L.featureGroup(markers).addTo(this.map)

    if (this.hasFocusValue && this.focusValue.length === 2) {
      this.map.setView(this.focusValue, markers.length > 1 ? 9 : 11)
    } else if (markers.length) {
      this.map.fitBounds(layer.getBounds(), { padding: [24, 24], maxZoom: 10 })
    } else {
      this.map.setView([30, 0], 2)
    }
  }

  disconnect() {
    this.map?.remove()
  }
}
