import { Controller } from "@hotwired/stimulus"

// Places as a three-step picker: continent, then country, then that country's posts by subdivision.
// The step lives in the URL hash (#europe/de), so back, reload and shared links all work.
// Without JS every section shows, which is a full list of places.
export default class extends Controller {
  static targets = [ "continents", "countries", "country", "crumbs", "crumbContinent", "crumbCountry" ]

  connect() {
    this.show = this.show.bind(this)
    window.addEventListener("hashchange", this.show)
    this.show()
  }

  disconnect() {
    window.removeEventListener("hashchange", this.show)
  }

  show() {
    const [ continentKey = "", countryKey = "", regionKey = "" ] = decodeURIComponent(location.hash.slice(1)).split("/")
    const countryPath = `${continentKey}/${countryKey}`
    const continents = this.countriesTargets.find(el => el.dataset.key === continentKey)
    const country = countryKey && this.countryTargets.find(el => el.dataset.key === countryPath)

    this.continentsTarget.hidden = !!continents
    this.countriesTargets.forEach(el => el.hidden = el !== continents || !!country)
    this.countryTargets.forEach(el => el.hidden = el !== country)

    this.crumbsTarget.hidden = !continents
    this.crumbContinentTarget.replaceChildren(...(continents ? this.crumb(`#${continentKey}`, this.nameFor(this.continentsTarget, `#${continentKey}`), !country) : []))
    this.crumbCountryTarget.replaceChildren(...(country ? this.crumb(`#${countryPath}`, this.nameFor(continents, `#${countryPath}`), !regionKey) : []))

    // A subdivision in the hash jumps to its section; the bare country goes back to the top of the list.
    const region = country && regionKey && [ ...country.querySelectorAll("[data-region-key]") ].find(el => el.dataset.regionKey === regionKey)
    // Wait a frame so this lands after Turbo's and the browser's own scroll for the hash.
    requestAnimationFrame(() => {
      if (region) region.scrollIntoView()
      else if (country) this.element.scrollIntoView()
    })
  }

  // " › Europe", linked unless it is the step being shown.
  crumb(href, name, current) {
    const el = document.createElement(current ? "b" : "a")
    if (!current) el.href = href
    el.textContent = name
    return [ " › ", el ]
  }

  nameFor(section, href) {
    return [ ...section.querySelectorAll("a") ].find(a => a.getAttribute("href") === href)?.dataset.name ?? ""
  }
}
