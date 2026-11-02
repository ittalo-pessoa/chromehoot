import { readFileSync } from "node:fs"
import vm from "node:vm"
import assert from "node:assert/strict"

class Element {
  constructor(tag) {
    this.tagName = tag
    this.children = []
    this.dataset = {}
    this.style = {}
    this.attributes = {}
    this.animations = 0
    this.listeners = {}
    this.className = ""
    this.classList = {
      add: name => this.classList.toggle(name, true),
      toggle: (name, value) => {
        const classes = new Set(this.className.split(" ").filter(Boolean))
        value ? classes.add(name) : classes.delete(name)
        this.className = [...classes].join(" ")
      }
    }
  }
  append(child) { this.children.push(child) }
  replaceChildren() { this.children = [] }
  setAttribute(key, value) { this.attributes[key] = value }
  addEventListener(name, fn) { this.listeners[name] = fn }
  animate() { this.animations++ }
  all() { return this.children.flatMap(child => [child, ...child.all()]) }
  querySelectorAll(selector) {
    return this.all().filter(node => selector === "button" ? node.tagName === "button" : selector === "[data-timer]" ? node.dataset.timer : false)
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] }
}
let now = 0
let reduced = false
const source = readFileSync("app/javascript/controllers/game_controller.js", "utf8")
  .replace(/^import .*\n/, "").replace("export default class", "globalThis.Game = class")
const context = vm.createContext({
  Controller: class {}, document: { createElement: tag => new Element(tag) },
  window: { matchMedia: () => ({ matches: reduced }) }, performance: { now: () => now },
  setInterval: () => 1, clearInterval() {}, clearTimeout() {}
})
vm.runInContext(source, context)
const game = new context.Game()
game.element = new Element("div")
game.contentTarget = new Element("section")
game.statusTarget = new Element("div")
game.roleValue = "student"
game.dispatch = () => {}
const state = {
  status: "running", server_time: "2026-11-02T12:00:00Z", answered: false,
  round: { id: 1, number: 2, total: 10, status: "open", closes_at: "2026-11-02T12:00:05Z" },
  question: { statement: "Qual componente armazena dados?", choices: [{ id: 1, letter: "A", text: "SSD" }, { id: 2, letter: "B", text: "CPU" }] }
}
game.render(state)
const progress = game.contentTarget.all().find(node => node.attributes.role === "progressbar")
assert.equal(progress.attributes["aria-valuenow"], "2")
assert.equal(progress.children[0].style.width, "20%")
const timer = game.contentTarget.querySelector("[data-timer]")
assert.match(timer.className, /timer-urgent/)
assert.equal(game.contentTarget.animations, 1)
const originalButton = game.contentTarget.querySelector("button")
game.render({ ...state, server_time: "2026-11-02T12:00:01Z" })
assert.equal(game.contentTarget.querySelector("button"), originalButton, "Clock updates preserve focusable answer buttons")
assert.equal(game.contentTarget.animations, 1, "Polling does not repeat entrance motion")
game.render({ ...state, server_time: "2026-11-02T12:00:05Z" })
assert.match(timer.className, /timer-ended/)
assert.ok(game.contentTarget.querySelectorAll("button").every(button => button.disabled))
game.render({ ...state, answered: true, result: { correct: true, points: 900 } })
assert.equal(game.contentTarget.querySelectorAll("button").length, 0)
assert.ok(!game.contentTarget.all().some(node => node.className.includes("success")), "No success feedback before reveal")
assert.ok(game.contentTarget.all().some(node => node.textContent?.includes("Resposta recebida")))
reduced = true
const animationCount = game.contentTarget.animations
game.render({ ...state, answered: true, round: { ...state.round, status: "revealed" }, result: { correct: true, points: 900 }, distribution: { 1: 1 }, correct_choice_id: 1 })
assert.ok(game.contentTarget.all().some(node => node.className.includes("success") && node.textContent.includes("900")))
assert.equal(game.contentTarget.animations, animationCount, "Reduced motion disables entrance animation")
console.log("Game: progress, timer, answer lock, reveal-only feedback, stable polling and reduced motion OK")
