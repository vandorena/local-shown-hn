// A Leaflet map of places with local posts: an orange square per place with its post count in it.
// Places that would overlap at the current zoom merge into one square with their total; zooming in splits them.
// points: [[lat, lng, label, url, count], ...]. focus: [lat, lng] to centre on (a place page).
import { Controller } from "@hotwired/stimulus"
import * as L from "leaflet"

const CELL = 44 // px: places closer than about this on screen share a square

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

    this.places = this.pointsValue.map(([ lat, lng, label, url, count ]) => ({ latlng: L.latLng(lat, lng), label, url, count }))
    this.layer = L.layerGroup().addTo(this.map)
    this.map.on("zoomend", () => this.draw())

    if (this.hasFocusValue && this.focusValue.length === 2) {
      this.map.setView(this.focusValue, this.places.length > 1 ? 9 : 11)
    } else if (this.places.length) {
      this.map.fitBounds(L.latLngBounds(this.places.map(p => p.latlng)), { padding: [ 24, 24 ], maxZoom: 10 })
    } else {
      this.map.setView([ 30, 0 ], 2)
    }
    this.draw()
  }

  disconnect() {
    this.map?.remove()
  }

  // Merge places that are within CELL px of each other on screen at this zoom, biggest first,
  // so a big city pulls in its suburbs. Then draw one square per group.
  draw() {
    const zoom = this.map.getZoom()
    const clusters = []
    for (const place of [ ...this.places ].sort((a, b) => b.count - a.count)) {
      const pt = this.map.project(place.latlng, zoom)
      const near = clusters.find(c => c.pt.distanceTo(pt) < CELL)
      if (near) near.places.push(place)
      else clusters.push({ pt, places: [ place ] })
    }

    this.layer.clearLayers()
    // Biggest last, so it sits on top where neighbouring squares touch.
    const groups = clusters.map(c => c.places).sort((a, b) => total(a) - total(b))
    for (const group of groups) this.layer.addLayer(group.length === 1 ? this.placeMarker(group[0]) : this.groupMarker(group))
  }

  placeMarker(place) {
    const popup = document.createElement("div")
    popup.append(this.link(place), document.createElement("br"), plural(place.count))
    return L.marker(place.latlng, { icon: badge(place.count), title: place.label, riseOnHover: true })
      .bindPopup(popup)
  }

  // A merged square sits at the post-weighted middle of its places; clicking zooms to fit them,
  // or lists them when they are too close to ever split.
  groupMarker(group) {
    const sum = total(group)
    const centre = L.latLng(
      group.reduce((s, p) => s + p.latlng.lat * p.count, 0) / sum,
      group.reduce((s, p) => s + p.latlng.lng * p.count, 0) / sum
    )
    const byCount = [ ...group ].sort((a, b) => b.count - a.count)
    const names = byCount.slice(0, 3).map(p => p.label.split(",")[0]).join(", ") + (group.length > 3 ? ` and ${group.length - 3} more` : "")
    const marker = L.marker(centre, { icon: badge(sum, true), title: `${names} (${plural(sum)})`, riseOnHover: true })

    const bounds = L.latLngBounds(group.map(p => p.latlng))
    const target = Math.min(this.map.getBoundsZoom(bounds, false, L.point(CELL * 2, CELL * 2)), this.map.getMaxZoom())
    if (target > this.map.getZoom()) {
      return marker.on("click", () => this.map.flyToBounds(bounds, { padding: [ CELL, CELL ], duration: 0.6 }))
    }

    const list = document.createElement("div")
    list.className = "map-list"
    for (const place of byCount) {
      const row = document.createElement("div")
      row.append(this.link(place), ` ${place.count}`)
      list.append(row)
    }
    return marker.bindPopup(list)
  }

  link(place) {
    const a = document.createElement("a")
    a.href = place.url
    a.textContent = place.label
    return a
  }
}

const total = group => group.reduce((s, p) => s + p.count, 0)
const plural = n => `${n} post${n === 1 ? "" : "s"}`

// The square itself; its CSS lives in application.css under .map-badge.
function badge(count, merged = false) {
  const text = count > 999 ? `${Math.round(count / 100) / 10}k` : String(count)
  const size = 18 + Math.max(0, text.length - 1) * 6
  return L.divIcon({
    className: `map-badge${merged ? " merged" : ""}`,
    html: `<span>${text}</span>`,
    iconSize: [ size, 18 ],
    iconAnchor: [ size / 2, 9 ]
  })
}
