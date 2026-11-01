import { readFileSync } from "node:fs"
import vm from "node:vm"
import assert from "node:assert/strict"

const script = readFileSync("app/assets/javascripts/theme_boot.js", "utf8")
function boot(saved, systemDark = false, blocked = false) {
  const events = {}
  const root = { dataset: {} }
  const picker = { value: "", matches: selector => selector === "[data-theme-picker]" }
  const stored = new Map(saved ? [["chromehoot-theme", saved]] : [])
  const document = { documentElement: root, querySelectorAll: () => [picker], addEventListener: (name, fn) => { events[name] = fn } }
  const window = { matchMedia: () => ({ matches: systemDark }), addEventListener: (name, fn) => { events[name] = fn } }
  const localStorage = { getItem: key => { if (blocked) throw new Error("blocked"); return stored.get(key) }, setItem: (key, value) => { if (blocked) throw new Error("blocked"); stored.set(key, value) } }
  vm.runInNewContext(script, { document, window, localStorage })
  return { root, picker, events, stored }
}
const saved = boot("dark")
assert.equal(saved.root.dataset.theme, "dark")
assert.equal(saved.picker.value, "dark")
saved.picker.value = "light"
saved.events.change({ target: saved.picker })
assert.equal(saved.root.dataset.theme, "light")
assert.equal(saved.stored.get("chromehoot-theme"), "light")
saved.events["turbo:load"]()
assert.equal(saved.root.dataset.theme, "light")
assert.equal(boot(null, true).root.dataset.theme, "dark")
assert.equal(boot("unexpected", false).root.dataset.theme, "light")
const blocked = boot(null, false, true)
blocked.picker.value = "dark"
blocked.events.change({ target: blocked.picker })
assert.equal(blocked.root.dataset.theme, "dark")
console.log("Theme: saved preference, toggle, Turbo navigation, system preference and blocked storage OK")
