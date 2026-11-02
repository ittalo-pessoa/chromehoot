import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "content"]
  static values = { url: String, answerUrl: String, role: String }

  connect() {
    this.stopped = false
    this.sending = false
    this.poll()
  }

  disconnect() {
    this.stopped = true
    clearTimeout(this.timeout)
    clearInterval(this.ticker)
    this.abort?.abort()
    clearTimeout(this.fetchTimeout)
  }

  async poll() {
    if (this.stopped) return
    this.abort = new AbortController()
    this.fetchTimeout = setTimeout(() => this.abort.abort(), 10000)
    let delay = 4000
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, cache: "no-store", signal: this.abort.signal })
      const state = await response.json()
      clearTimeout(this.fetchTimeout)
      if (!response.ok) throw new Error(state.error || "Não foi possível carregar a sala.")
      if (this.stopped) return
      this.render(state)
      delay = state.round?.status === "open" || this.roleValue === "teacher" ? 2000 : 4000
      if (["finished", "cancelled", "removed"].includes(state.status)) return
    } catch (error) {
      clearTimeout(this.fetchTimeout)
      if (this.stopped) return
      this.statusTarget.textContent = `${error.message} Tentando reconectar…`
    }
    if (!this.stopped) this.timeout = setTimeout(() => this.poll(), delay)
  }

  node(tag, text, className) {
    const element = document.createElement(tag)
    if (text !== undefined) element.textContent = text
    if (className) element.className = className
    return element
  }

  render(state) {
    this.dispatch("state", { detail: state })
    const labels = { waiting: this.roleValue === "teacher" ? "Sala aberta · convide a turma e inicie quando todos estiverem prontos" : "Sala de espera · aguarde o professor", running: "Partida em andamento", finished: "Partida finalizada", cancelled: "Partida cancelada", removed: "Sua participação foi encerrada pelo professor" }
    this.statusTarget.textContent = labels[state.status]
    const round = state.round
    const phase = `${state.status}:${round?.id}:${round?.status}:${Boolean(state.answered)}`
    const phaseChanged = this.phase !== phase
    this.phase = phase
    this.element.querySelectorAll("[data-game-round]").forEach(input => { input.value = round?.id || "" })
    const permitted = { start: state.status === "waiting", open_question: round?.status === "pending", close_question: round?.status === "open", reveal: round?.status === "closed", advance: round?.status === "revealed", finish: true, cancel: true }
    this.element.querySelectorAll("[data-game-command]").forEach(form => { form.querySelector("input[type=submit]").disabled = ["finished", "cancelled"].includes(state.status) || !permitted[form.dataset.gameCommand] })
    // Preserve keyboard focus and answer buttons while only the clock changes.
    const signature = JSON.stringify({ ...state, server_time: null })
    this.remaining = round?.closes_at ? Math.max(0, Date.parse(round.closes_at) - Date.parse(state.server_time)) : 0
    this.clockAt = performance.now()
    if (signature !== this.signature) {
      this.signature = signature
      const content = this.contentTarget
      content.replaceChildren()
      if (state.status === "removed") return
      if (state.summary) {
        this.renderSummary(content, state.summary)
      } else if (state.status === "waiting") {
        const waiting = this.node("div", undefined, "waiting-art")
        waiting.append(this.node("span", "✦"))
        waiting.append(this.node("h2", "A turma está chegando!"))
        waiting.append(this.node("p", `${state.participants.length} participantes na sala · o desafio já vai começar.`))
        content.append(waiting)
        const chips = this.node("div", undefined, "participant-chips")
        state.participants.forEach(name => chips.append(this.node("span", name, "participant-chip")))
        if (!state.participants.length) chips.append(this.node("p", "Compartilhe o código para convidar os alunos."))
        content.append(chips)
      } else if (round?.status === "pending") {
        content.append(this.node("div", "⚑", "auth-emblem"))
        content.append(this.node("h2", "Prepare-se! A próxima questão será aberta pelo professor."))
      } else if (state.question) {
        content.append(this.node("p", `Questão ${round.number} de ${round.total}`, "question-progress"))
        const progress = this.node("div", undefined, "round-progress")
        progress.setAttribute("role", "progressbar")
        progress.setAttribute("aria-label", "Progresso da partida")
        progress.setAttribute("aria-valuemin", "0")
        progress.setAttribute("aria-valuemax", String(round.total))
        progress.setAttribute("aria-valuenow", String(round.number))
        const fill = this.node("span", undefined, "round-progress-fill")
        fill.style.width = `${Math.max(0, Math.min(100, round.number / round.total * 100))}%`
        progress.append(fill)
        content.append(progress)
        content.append(this.node("h2", state.question.statement))
        if (state.question.image_url) {
          const image = this.node("img", undefined, "question-image")
          image.src = state.question.image_url
          image.alt = "Imagem da questão"
          content.append(image)
        }
        if (round.status === "open" && state.status === "running") {
          const timer = this.node("p", "", "timer")
          timer.dataset.timer = "true"
          content.append(timer)
        }
        const options = this.node("div", undefined, "options")
        state.question.choices.forEach(choice => {
          const selectable = this.roleValue === "student" && round.status === "open" && state.status === "running" && !state.answered
          const option = this.node(selectable ? "button" : "div", undefined, "option")
          option.append(this.node("span", choice.letter, "choice-symbol"))
          const text = this.node("div", undefined, "choice-text")
          text.append(this.node("span", choice.text))
          option.append(text)
          if (selectable) {
            option.type = "button"
            option.disabled = this.sending
            option.addEventListener("click", () => this.answer(round.id, choice.id))
          }
          if (round.status === "revealed") {
            const count = state.distribution[choice.id] || 0
            const total = Object.values(state.distribution).reduce((sum, value) => sum + value, 0)
            if (choice.id === state.correct_choice_id) option.classList.add("correct-option")
            text.append(this.node("span", `${choice.id === state.correct_choice_id ? "✓ Correta · " : ""}${count} respostas${total ? ` (${Math.round(count * 100 / total)}%)` : ""}`, "choice-result"))
            const bar = this.node("span", undefined, "distribution-bar")
            const fill = this.node("span", undefined, "distribution-fill")
            fill.style.width = `${total ? count * 100 / total : 0}%`
            bar.append(fill)
            text.append(bar)
          }
          options.append(option)
        })
        content.append(options)
        if (state.answered && round.status !== "revealed") content.append(this.node("p", "✓ Resposta recebida! Aguarde a revelação.", "answer-feedback"))
        if (round.status === "closed") content.append(this.node("p", "Respostas encerradas. Aguarde a revelação.", "answer-feedback"))
        if (round.status === "revealed" && state.result) content.append(this.node("p", state.result.correct ? `★ Você acertou! +${state.result.points} pontos` : "Desta vez não foi. Vamos para a próxima!", `answer-feedback ${state.result.correct ? "success" : "encouragement"}`))
        if (state.answer_count !== undefined && this.roleValue === "teacher") content.append(this.node("p", `${state.answer_count} respostas recebidas`))
      }
      if (state.ranking) {
        content.append(this.node("h2", state.status === "finished" ? "Pódio e placar final" : "Placar · resultados revelados", "ranking-heading"))
        const list = this.node("div", undefined, "ranking-list")
        state.ranking.forEach(row => {
          const item = this.node("div", undefined, `ranking-row${row.rank <= 3 ? " podium" : ""}`)
          item.append(this.node("span", `${row.rank}º`, "rank-number"))
          item.append(this.node("span", row.nickname, "rank-name"))
          item.append(this.node("span", `${row.correct} acertos`, "rank-detail"))
          item.append(this.node("span", `${row.points} pts`, "rank-score"))
          list.append(item)
        })
        content.append(list)
      }
      if (phaseChanged && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
        content.animate?.([{ opacity: 0.5, transform: "translateY(8px)" }, { opacity: 1, transform: "translateY(0)" }], { duration: 240, easing: "ease-out" })
      }
    }
    clearInterval(this.ticker)
    const tick = () => {
      const timer = this.contentTarget.querySelector("[data-timer]")
      if (!timer) return
      const seconds = Math.max(0, Math.ceil((this.remaining - (performance.now() - this.clockAt)) / 1000))
      timer.textContent = `◷ ${seconds}s restantes`
      timer.classList.toggle("timer-urgent", seconds > 0 && seconds <= 5)
      timer.classList.toggle("timer-ended", seconds === 0)
      if (!seconds) this.contentTarget.querySelectorAll("button").forEach(button => { button.disabled = true })
    }
    tick()
    this.ticker = setInterval(tick, 250)
  }

  renderSummary(content, summary) {
    const banner = this.node("div", undefined, "finish-banner")
    banner.append(this.node("div", "★", "finish-medal"))
    banner.append(this.node("h2", `Parabéns, ${summary.nickname}!`))
    banner.append(this.node("p", "Você concluiu o desafio. Cada pergunta é uma nova descoberta!"))
    content.append(banner)
    const stats = this.node("div", undefined, "result-stats")
    const values = [[`${summary.correct} / ${summary.total}`, "acertos", "green"], [`${summary.rank}º`, "sua posição", "amber"], [summary.points, "pontos", "violet"]]
    values.forEach(([value, label, color]) => {
      const stat = this.node("div", undefined, `result-stat ${color}`)
      stat.append(this.node("strong", value))
      stat.append(this.node("span", label))
      stats.append(stat)
    })
    content.append(stats)
    content.append(this.node("h3", "Sua jornada, questão por questão"))
    const history = this.node("div", undefined, "question-history")
    summary.questions.forEach(question => {
      const item = this.node("div", undefined, "history-item")
      const outcome = question.correct === true ? "Acerto" : question.correct === false ? "Erro" : "Sem resposta"
      const dot = this.node("span", question.correct === true ? "✓" : question.correct === false ? "×" : "−", `history-dot ${question.correct === true ? "right" : question.correct === false ? "wrong" : ""}`)
      dot.setAttribute("aria-label", `Questão ${question.number}: ${outcome}`)
      dot.title = outcome
      item.append(dot)
      item.append(this.node("span", question.number))
      history.append(item)
    })
    content.append(history)
  }

  async answer(roundId, choiceId) {
    if (this.sending) return
    this.sending = true
    this.contentTarget.querySelectorAll("button").forEach(button => { button.disabled = true })
    try {
      const response = await fetch(this.answerUrlValue, {
        method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
        body: JSON.stringify({ round_id: roundId, choice_id: choiceId })
      })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error)
      this.statusTarget.textContent = "✓ Resposta recebida! Aguarde a revelação."
    } catch (error) {
      this.statusTarget.textContent = `${error.message || "Falha de rede."} O estado será atualizado automaticamente.`
    } finally {
      this.sending = false
      this.signature = null
    }
  }
}
