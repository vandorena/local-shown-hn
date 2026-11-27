import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as a field changes, e.g. the map's "show all projects" box.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
