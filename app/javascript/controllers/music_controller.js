import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "message"]
  static values = { url: String }

  connect() {
    this.audio = new Audio(this.urlValue)
    this.audio.loop = true
    this.audio.volume = 0.08
    this.audio.preload = "none"
    this.enabled = false
    this.active = false
    this.onError = () => {
      this.enabled = false
      this.audio.pause()
      this.updateButton()
      this.messageTarget.textContent = "Não foi possível tocar este áudio. A partida continua normalmente."
    }
    this.audio.addEventListener("error", this.onError)
  }

  disconnect() {
    clearTimeout(this.deadline)
    this.enabled = false
    this.active = false
    this.audio.pause()
    this.audio.removeEventListener("error", this.onError)
    this.audio.removeAttribute("src")
    this.audio.load()
  }

  toggle() {
    this.enabled = !this.enabled
    this.updateButton()
    if (this.enabled) {
      // The explicit click authorizes media playback before the question starts.
      this.play()
    } else {
      this.audio.pause()
      this.messageTarget.textContent = "Música silenciada."
    }
  }

  sync({ detail: state }) {
    clearTimeout(this.deadline)
    const remaining = Date.parse(state.round?.closes_at) - Date.parse(state.server_time)
    this.active = state.status === "running" && state.round?.status === "open" && remaining > 0
    if (this.active) {
      this.deadline = setTimeout(() => { this.active = false; this.audio.pause() }, remaining)
    }
    if (this.active && this.enabled) {
      if (this.audio.paused) this.play()
    } else {
      this.audio.pause()
      if (this.enabled) this.messageTarget.textContent = "Som ativado. Aguardando a próxima pergunta."
    }
  }

  volume(event) {
    this.audio.volume = Math.max(0, Math.min(0.2, Number(event.target.value) / 100))
  }

  async play() {
    try {
      this.audio.muted = !this.active
      await this.audio.play()
      if (!this.enabled || !this.active) this.audio.pause()
      this.audio.muted = false
      if (!this.enabled) return
      this.messageTarget.textContent = this.active ? "♫ Música de fundo ligada" : "Som ativado. A música começa quando a questão abrir."
    } catch {
      if (!this.enabled) return
      this.enabled = false
      this.updateButton()
      this.messageTarget.textContent = "O navegador não iniciou o áudio. Clique em Ativar música para tentar novamente."
    }
  }

  updateButton() {
    this.toggleTarget.textContent = this.enabled ? "♫ Silenciar música" : "♫ Ativar música"
    this.toggleTarget.setAttribute("aria-pressed", String(this.enabled))
  }
}
