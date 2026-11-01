import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "message"]
  static values = { url: String }

  connect() { this.stopped = false; this.poll() }
  disconnect() {
    this.stopped = true
    clearTimeout(this.timer)
    clearTimeout(this.deadline)
    this.abort?.abort()
  }

  async poll() {
    if (this.stopped) return
    this.abort = new AbortController()
    this.deadline = setTimeout(() => this.abort.abort(), 10000)
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, cache: "no-store", signal: this.abort.signal })
      if (response.status === 404) {
        this.titleTarget.textContent = "Pedido excluído"
        this.messageTarget.textContent = "Este pedido não está mais na fila. Volte aos seus pedidos para criar outro."
        return
      }
      if (!response.ok) throw new Error("Falha ao consultar pedido")
      const state = await response.json()
      if (this.stopped) return
      if (["ready", "failed", "imported"].includes(state.status)) {
        window.location.reload()
        return
      }
      this.titleTarget.textContent = state.status === "processing" ? "Preparando as questões…" : "Seu pedido está na fila"
      this.messageTarget.textContent = "Você pode sair desta página e voltar pelos seus pedidos. O quiz só será salvo após sua revisão."
    } catch {
      if (this.stopped) return
      this.messageTarget.textContent = "Conexão interrompida. Tentando novamente…"
    } finally {
      clearTimeout(this.deadline)
    }
    if (!this.stopped) this.timer = setTimeout(() => this.poll(), 3000)
  }
}
