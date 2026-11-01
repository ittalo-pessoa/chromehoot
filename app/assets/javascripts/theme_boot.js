// Served locally before the stylesheet to restore the theme without a light flash.
(() => {
  if (window.chromehootThemeReady) return
  window.chromehootThemeReady = true
  const key = "chromehoot-theme"
  const valid = value => value === "dark" || value === "light"
  const preferred = () => {
    try {
      const saved = localStorage.getItem(key)
      if (valid(saved)) return saved
    } catch (_) { /* The theme still works when storage is blocked. */ }
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }
  const apply = theme => {
    document.documentElement.dataset.theme = theme
    document.querySelectorAll("[data-theme-picker]").forEach(picker => { picker.value = theme })
  }
  apply(preferred())
  document.addEventListener("turbo:load", () => apply(preferred()))
  document.addEventListener("DOMContentLoaded", () => apply(preferred()))
  document.addEventListener("change", event => {
    if (!event.target.matches("[data-theme-picker]") || !valid(event.target.value)) return
    const theme = event.target.value
    try { localStorage.setItem(key, theme) } catch (_) { /* Optional persistence. */ }
    apply(theme)
  })
  window.addEventListener("storage", event => { if (event.key === key) apply(preferred()) })
})()
