import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRuntimeAudio } from '../assets/game3d/runtime-audio.mjs';

const runtime = fs.readFileSync(new URL('../assets/game3d/runtime.js', import.meta.url), 'utf8');
assert.match(runtime, /if \(reaction\?\.ok !== false\) \{\s*void runtimeAudio\.playPet\(state\.species\);/);

class Node {
  connect() {}
  disconnect() {}
}

class Source extends Node {
  start() { this.started = true; }
  stop() { this.stopped = true; this.onended?.(); }
  finish() { this.onended?.(); }
}

class Context {
  state = 'running';
  destination = {};
  sources = [];
  createBufferSource() {
    const source = new Source();
    this.sources.push(source);
    return source;
  }
  createGain() { return Object.assign(new Node(), { gain: { value: 1 } }); }
  async decodeAudioData() { return {}; }
  async close() {}
}

const context = new Context();
const requests = [];
let now = 1000;
let releaseFirst;
const audio = createRuntimeAudio({
  contextFactory: () => context,
  now: () => now,
  fetchImpl: (url) => {
    requests.push(url.pathname);
    if (requests.length === 1) return new Promise((resolve) => { releaseFirst = resolve; });
    return Promise.resolve({ ok: true, arrayBuffer: async () => new ArrayBuffer(8) });
  },
});

assert.equal(await audio.playPet('unknown'), false);
const first = audio.playPet('kitten');
assert.equal(await audio.playPet('puppy'), false, 'a loading pet sound reserves the channel');
releaseFirst({ ok: true, arrayBuffer: async () => new ArrayBuffer(8) });
assert.equal(await first, true);
assert.match(requests[0], /kitten_mew\.ogg$/);
assert.equal(await audio.playPet('hamster'), false, 'an active pet sound cannot overlap');
context.sources[0].finish();
assert.equal(await audio.playPet('kitten'), false, 'repeated tap respects the cooldown');
now += 1000;
assert.equal(await audio.playPet('puppy'), true);
assert.match(requests[1], /puppy_bark\.mp3$/);
audio.setEnabled(false);
assert.equal(context.sources[1].stopped, true);
assert.equal(await audio.playPet('hamster'), false);
audio.setEnabled(true);
now += 1000;
assert.equal(await audio.playPet('hamster'), true);
assert.match(requests[2], /hamster_squeak\.mp3$/);
audio.setPaused(true);
assert.equal(context.sources[2].stopped, true);
assert.equal(await audio.playPet('kitten'), false);
await audio.dispose();
console.log('pet audio mapping, pending/active exclusion, cooldown, mute and pause passed');
