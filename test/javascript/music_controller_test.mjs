import { readFileSync } from "node:fs"
import vm from "node:vm"
import assert from "node:assert/strict"

class AudioStub {
  constructor() { this.paused = true; this.plays = 0 }
  addEventListener() {}
  removeEventListener() {}
  removeAttribute() {}
  load() {}
  pause() { this.paused = true }
  async play() { this.plays++; this.paused = false; if (this.blocked) throw new Error("NotAllowedError") }
}
const source = readFileSync("app/javascript/controllers/music_controller.js", "utf8")
  .replace(/^import .*\n/, "")
  .replace("export default class", "globalThis.Music = class")
const context = vm.createContext({ Controller: class {}, Audio: AudioStub, setTimeout, clearTimeout })
vm.runInContext(source, context)
const player = new context.Music()
player.urlValue = "/local.wav"
player.toggleTarget = { textContent: "", setAttribute() {} }
player.messageTarget = { textContent: "" }
player.connect()
assert.equal(player.audio.volume, 0.05)
assert.equal(player.audio.loop, true)
const state = status => ({ detail: { status: "running", server_time: new Date().toISOString(), round: { status, closes_at: new Date(Date.now() + 30000).toISOString() } } })
player.sync(state("open"))
assert.equal(player.audio.plays, 0, "No sound without an explicit user click")
player.toggle()
await new Promise(resolve => setImmediate(resolve))
assert.equal(player.audio.paused, false)
player.sync(state("closed"))
assert.equal(player.audio.paused, true)
player.sync(state("open"))
await new Promise(resolve => setImmediate(resolve))
assert.equal(player.audio.paused, false)
player.volume({ target: { value: 20 } })
assert.equal(player.audio.volume, 0.2)
player.toggle()
assert.equal(player.audio.paused, true)
player.sync(state("open"))
assert.equal(player.audio.paused, true)
player.audio.blocked = true
player.toggle()
await new Promise(resolve => setImmediate(resolve))
assert.equal(player.enabled, false, "Playback rejection resets the control")
player.disconnect()
assert.equal(player.audio.paused, true)
console.log("Music: opt-in, low volume, loop, question transitions, mute, blocked playback and cleanup OK")
