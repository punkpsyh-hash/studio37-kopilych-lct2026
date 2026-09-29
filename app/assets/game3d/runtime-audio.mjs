const AUDIO_ROOT = new URL('../audio/free-2026-09-26/', import.meta.url);

// Runtime gain is deliberately conservative until the mix is checked on a
// physical Android device. Contact-only loop windows avoid replaying the
// faucet/sponge onset while movement or water flow remains active. Every loop
// is still stopped by pointer release, pause, cancel, mute or disposal.
export const AUDIO_CUES = Object.freeze({
  uiTap: Object.freeze({ file: 'ui_tap.ogg', gain: 0.16, cooldownMs: 80 }),
  uiBack: Object.freeze({ file: 'ui_back.ogg', gain: 0.14, cooldownMs: 120 }),
  uiConfirm: Object.freeze({ file: 'ui_confirm.ogg', gain: 0.17, cooldownMs: 220 }),
  uiReward: Object.freeze({ file: 'ui_reward.ogg', gain: 0.14, cooldownMs: 1400 }),
  coinSave: Object.freeze({ file: 'coin_save.ogg', gain: 0.17, cooldownMs: 900 }),
  clothFold: Object.freeze({ file: 'cloth_fold.ogg', gain: 0.20, cooldownMs: 280 }),
  clothPlace: Object.freeze({ file: 'cloth_place.ogg', gain: 0.18, cooldownMs: 280 }),
  dishPlace: Object.freeze({ file: 'dish_place.ogg', gain: 0.10, cooldownMs: 800 }),
  faucetOff: Object.freeze({ file: 'faucet_off_candidate.ogg', gain: 0.32, cooldownMs: 800 }),
  boxLid: Object.freeze({ file: 'box_lid.ogg', gain: 0.17, cooldownMs: 800 }),
  boxPop: Object.freeze({ file: 'box_pop.ogg', gain: 0.13, cooldownMs: 500 }),
  waterRinse: Object.freeze({ file: 'water_rinse.ogg', gain: 0.15, cooldownMs: 900 }),
  broomSweep: Object.freeze({ file: 'broom_sweep_candidate.ogg', gain: 0.12, cooldownMs: 650 }),
  spongeScrub: Object.freeze({ file: 'sponge_squeeze_candidate.ogg', gain: 0.36, cooldownMs: 180,
    contactLoop: Object.freeze({ start: 0.327375, end: 1.684292 }) }),
  clothWipe: Object.freeze({ file: 'cloth_fold.ogg', gain: 0.12, cooldownMs: 180 }),
  waterFlow: Object.freeze({ file: 'faucet_rinse_candidate.ogg', gain: 0.32, cooldownMs: 180,
    contactLoop: Object.freeze({ start: 0.916708, end: 2.313542 }) }),
  bubblePop: Object.freeze({ file: 'box_pop.ogg', gain: 0.07, cooldownMs: 280 }),
  kittenMew: Object.freeze({ file: 'kitten_mew.ogg', gain: 0.30, cooldownMs: 900 }),
  puppyBark: Object.freeze({ file: 'puppy_bark.mp3', gain: 0.30, cooldownMs: 900 }),
  hamsterSqueak: Object.freeze({ file: 'hamster_squeak.mp3', gain: 0.28, cooldownMs: 900 }),
});

const CONTACT_CUES = new Set(['spongeScrub', 'clothWipe', 'broomSweep', 'waterFlow']);
const CONTACT_IDLE_MS = 150;
const PET_CUES = Object.freeze({ kitten: 'kittenMew', puppy: 'puppyBark', hamster: 'hamsterSqueak' });

function defaultContextFactory() {
  const AudioContext = globalThis.AudioContext || globalThis.webkitAudioContext;
  return AudioContext ? new AudioContext() : null;
}

function defaultNow() {
  return globalThis.performance?.now?.() ?? Date.now();
}

/** A bounded, best-effort one-shot player for the embedded scene. */
export class RuntimeAudio {
  constructor({
    contextFactory = defaultContextFactory,
    fetchImpl = globalThis.fetch?.bind(globalThis),
    now = defaultNow,
    baseUrl = AUDIO_ROOT,
    maxVoices = 3,
    setTimer = globalThis.setTimeout.bind(globalThis),
    clearTimer = globalThis.clearTimeout.bind(globalThis),
  } = {}) {
    this._contextFactory = contextFactory;
    this._fetch = fetchImpl;
    this._now = now;
    this._baseUrl = baseUrl;
    this._maxVoices = maxVoices;
    this._buffers = new Map();
    this._sources = new Set();
    this._lastStarted = new Map();
    this._context = null;
    this._enabled = true;
    this._volume = 100;
    this._masterGain = null;
    this._paused = false;
    this._disposed = false;
    this._generation = 0;
    this._setTimer = setTimer;
    this._clearTimer = clearTimer;
    this._contact = null;
    this._contactTimer = null;
    this._petSoundActive = false;
  }

  get enabled() {
    return this._enabled;
  }

  async play(cueId, contact = null, onEnd = null) {
    const cue = AUDIO_CUES[cueId];
    if (!cue || !this._enabled || this._paused || this._disposed || !this._fetch) return false;
    const now = this._now();
    const previous = this._lastStarted.get(cueId) ?? -Infinity;
    if (now - previous < cue.cooldownMs) return false;
    // Reserve the cooldown before loading so repeated taps cannot fan out while
    // the first file is still being decoded.
    this._lastStarted.set(cueId, now);
    const generation = this._generation;
    let voice;

    try {
      const context = this._context ??= this._contextFactory();
      if (!context) return false;
      if (context.state === 'suspended') await context.resume();
      const buffer = await this._load(cue.file, context);
      if (generation !== this._generation || !this._enabled || this._paused || this._disposed
          || (contact && this._contact !== contact)) return false;

      if (this._sources.size >= this._maxVoices) this._stop(this._sources.values().next().value);
      const source = context.createBufferSource();
      const gain = context.createGain();
      if (!this._masterGain) {
        this._masterGain = context.createGain();
        this._masterGain.gain.value = this._volume / 100;
        this._masterGain.connect(context.destination);
      }
      source.buffer = buffer;
      const contactLoop = contact ? cue.contactLoop : null;
      source.loop = Boolean(contactLoop);
      if (contactLoop) {
        source.loopStart = contactLoop.start;
        source.loopEnd = contactLoop.end;
      }
      gain.gain.value = cue.gain;
      source.connect(gain);
      gain.connect(this._masterGain);
      voice = { source, gain, onEnd };
      this._sources.add(voice);
      if (contact) contact.voice = voice;
      source.onended = () => this._release(voice);
      source.start(0);
      return true;
    } catch (_) {
      if (voice) this._release(voice);
      // Sound is optional: a decode or Web Audio failure must never block play.
      return false;
    }
  }

  // Reserve the pet channel while the file loads as well as while it plays.
  // This keeps rapid taps and different species from stacking or starting late.
  async playPet(species) {
    const cueId = PET_CUES[species];
    if (!cueId || this._petSoundActive) return false;
    this._petSoundActive = true;
    const started = await this.play(cueId, null, () => { this._petSoundActive = false; });
    if (!started) this._petSoundActive = false;
    return started;
  }

  // Call only while a moving tool actually touches its working surface. An
  // idle pointer, missed surface, cancelled gesture or slow decode stays quiet.
  contact(cueId) {
    if (!CONTACT_CUES.has(cueId) || !this._enabled || this._paused || this._disposed) {
      this.stopContact();
      return false;
    }
    if (this._contact?.cueId !== cueId) {
      this.stopContact();
      this._contact = { cueId, voice: null, pending: false };
    }
    const contact = this._contact;
    if (this._contactTimer !== null) this._clearTimer(this._contactTimer);
    this._contactTimer = this._setTimer(() => this.stopContact(), CONTACT_IDLE_MS);
    if (!contact.voice && !contact.pending) {
      contact.pending = true;
      void this.play(cueId, contact).finally(() => { contact.pending = false; });
    }
    return true;
  }

  stopContact() {
    if (this._contactTimer !== null) this._clearTimer(this._contactTimer);
    this._contactTimer = null;
    const voice = this._contact?.voice;
    this._contact = null;
    if (!voice) return;
    const time = this._context?.currentTime;
    if (Number.isFinite(time) && voice.gain.gain.setTargetAtTime) {
      try {
        voice.gain.gain.setTargetAtTime(0, time, 0.012);
        voice.source.stop(time + 0.04);
        return;
      } catch (_) {
        // A finished or unavailable context falls back to immediate cleanup.
      }
    }
    this._stop(voice);
  }

  async _load(file, context) {
    let pending = this._buffers.get(file);
    if (!pending) {
      pending = (async () => {
        const response = await this._fetch(new URL(file, this._baseUrl));
        if (!response.ok) throw new Error(`Audio asset failed: ${response.status}`);
        return context.decodeAudioData(await response.arrayBuffer());
      })();
      this._buffers.set(file, pending);
      pending.catch(() => this._buffers.delete(file));
    }
    return pending;
  }

  setEnabled(value) {
    this._enabled = value === true;
    if (!this._enabled) this.stopAll();
    return { enabled: this._enabled };
  }

  setVolume(value) {
    if (Number.isFinite(value)) {
      this._volume = Math.max(0, Math.min(100, Math.round(value)));
      if (this._masterGain) this._masterGain.gain.value = this._volume / 100;
    }
    return { volume: this._volume };
  }

  setPaused(value) {
    this._paused = value === true;
    if (this._paused) {
      this.stopAll();
      void this._context?.suspend?.().catch?.(() => {});
    }
    return { paused: this._paused };
  }

  stopAll() {
    this._generation += 1;
    this.stopContact();
    for (const voice of [...this._sources]) this._stop(voice);
  }

  _stop(voice) {
    if (!voice) return;
    try {
      voice.source.stop();
    } catch (_) {
      // A source that ended between scheduling and stop is already silent.
    }
    this._release(voice);
  }

  _release(voice) {
    if (!this._sources.delete(voice)) return;
    if (this._contact?.voice === voice) this._contact.voice = null;
    voice.onEnd?.();
    voice.source.onended = null;
    voice.source.disconnect?.();
    voice.gain.disconnect?.();
  }

  async dispose() {
    if (this._disposed) return;
    this._disposed = true;
    this.stopAll();
    const context = this._context;
    this._context = null;
    this._masterGain?.disconnect?.();
    this._masterGain = null;
    try {
      await context?.close?.();
    } catch (_) {
      // The page can be torn down while the platform audio context is closing.
    }
    this._buffers.clear();
  }
}

export function createRuntimeAudio(options) {
  return new RuntimeAudio(options);
}
