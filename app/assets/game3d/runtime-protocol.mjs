const ROOMS = new Set(['living', 'kitchen', 'bathroom']);
const SPECIES = new Set(['kitten', 'puppy', 'hamster']);
const WEARABLES = new Set(['cap', 'bow']);
const ACTIONS = new Set(['feed', 'water', 'play', 'clean', 'lamp', 'stars', 'nightlight', 'room', 'wash_dishes', 'complete_job']);
const MODES = new Set(['home', 'adoption']);
const JOB_IDS = new Set(['J01', 'J02', 'J03', 'J04', 'J05', 'J06']);
const SAFE_ID = /^[a-z0-9_.:-]{1,96}$/i;

export const API_VERSION = 1;

export const JOB_DEFINITIONS = Object.freeze({
  J01: Object.freeze({ room: 'kitchen', title: 'Чистая посуда', steps: Object.freeze(['scrub', 'scrub', 'scrub', 'scrub', 'scrub', 'scrub', 'rinse', 'water_off']) }),
  J02: Object.freeze({ room: 'living', title: 'Всё на месте', steps: Object.freeze(['sort', 'sort', 'sort']) }),
  J03: Object.freeze({ room: 'bathroom', title: 'Полотенца по местам', steps: Object.freeze(['fold', 'fold', 'shelf', 'shelf']) }),
  J04: Object.freeze({ room: 'kitchen', title: 'Разбираем упаковки', steps: Object.freeze(['sort', 'sort', 'sort', 'sort']) }),
  J05: Object.freeze({ room: 'living', title: 'Полки к новоселью', steps: Object.freeze(['wipe', 'wipe', 'wipe', 'put_away']) }),
  J06: Object.freeze({ room: 'living', title: 'Подметём вместе', steps: Object.freeze(['sweep', 'sweep', 'sweep', 'empty', 'put_away', 'put_away']) }),
});

export class ProtocolError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'ProtocolError';
    this.code = code;
  }
}

export const DEFAULT_STATE = Object.freeze({
  mode: 'home',
  adoptionOpen: false,
  room: 'living',
  species: 'kitten',
  color: 'fur_01',
  wearable: null,
  stage: 1,
  owned: Object.freeze([]),
  purchased: Object.freeze([]),
  lampOn: true,
  starsOn: true,
  nightlightOn: true,
  reducedMotion: false,
  busy: false,
  jobsAllowed: false,
  jobPeriod: 0,
  selectedJobId: null,
  viewportInsets: Object.freeze({ top: 0, bottom: 0, left: 0, right: 0 }),
});

function randomPart() {
  const cryptoApi = globalThis.crypto;
  if (cryptoApi && typeof cryptoApi.randomUUID === 'function') {
    return cryptoApi.randomUUID().replaceAll('-', '').slice(0, 16);
  }
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
}

function validateIdList(value, field) {
  if (!Array.isArray(value)) {
    throw new ProtocolError('INVALID_STATE', `${field} must be an array`);
  }
  const result = [];
  const seen = new Set();
  for (const entry of value) {
    if (typeof entry !== 'string' || !SAFE_ID.test(entry)) {
      throw new ProtocolError('INVALID_STATE', `${field} contains an invalid id`);
    }
    if (!seen.has(entry)) {
      seen.add(entry);
      result.push(entry);
    }
  }
  return result;
}

export function normalizeStatePatch(patch) {
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) {
    throw new ProtocolError('INVALID_STATE', 'setState expects one object');
  }
  const next = {};
  if ('mode' in patch) {
    if (!MODES.has(patch.mode)) throw new ProtocolError('INVALID_STATE', 'unknown mode');
    next.mode = patch.mode;
  }
  if ('room' in patch) {
    if (!ROOMS.has(patch.room)) throw new ProtocolError('INVALID_STATE', 'unknown room');
    next.room = patch.room;
  }
  if ('species' in patch) {
    if (!SPECIES.has(patch.species)) throw new ProtocolError('INVALID_STATE', 'unknown species');
    next.species = patch.species;
  }
  if ('color' in patch) {
    if (typeof patch.color !== 'string' || !SAFE_ID.test(patch.color)) {
      throw new ProtocolError('INVALID_STATE', 'invalid color id');
    }
    next.color = patch.color;
  }
  if ('wearable' in patch) {
    const wearable = patch.wearable === 'none' ? null : patch.wearable;
    if (wearable !== null && !WEARABLES.has(wearable)) {
      throw new ProtocolError('INVALID_STATE', 'unknown wearable');
    }
    next.wearable = wearable;
  }
  if ('stage' in patch) {
    if (!Number.isInteger(patch.stage) || patch.stage < 1 || patch.stage > 3) {
      throw new ProtocolError('INVALID_STATE', 'stage must be 1, 2, or 3');
    }
    next.stage = patch.stage;
  }
  if ('jobPeriod' in patch) {
    if (!Number.isInteger(patch.jobPeriod) || patch.jobPeriod < 0 || patch.jobPeriod > 1000000) {
      throw new ProtocolError('INVALID_STATE', 'jobPeriod must be a nonnegative integer');
    }
    next.jobPeriod = patch.jobPeriod;
  }
  if ('selectedJobId' in patch) {
    if (patch.selectedJobId !== null && !JOB_IDS.has(patch.selectedJobId)) {
      throw new ProtocolError('INVALID_STATE', 'selectedJobId must be J01-J06 or null');
    }
    next.selectedJobId = patch.selectedJobId;
  }
  if ('viewportInsets' in patch) {
    const insets = patch.viewportInsets;
    const left = insets?.left ?? 0;
    const right = insets?.right ?? 0;
    if (!insets || typeof insets !== 'object' || Array.isArray(insets) ||
        !Number.isFinite(insets.top) || !Number.isFinite(insets.bottom) ||
        !Number.isFinite(left) || !Number.isFinite(right) ||
        insets.top < 0 || insets.bottom < 0 || insets.top > 0.45 || insets.bottom > 0.45 ||
        left < 0 || right < 0 || left > 0.45 || right > 0.45 ||
        insets.top + insets.bottom >= 0.85 || left + right >= 0.75) {
      throw new ProtocolError('INVALID_STATE', 'viewportInsets must contain safe top, bottom, left and right fractions');
    }
    next.viewportInsets = { top: insets.top, bottom: insets.bottom, left, right };
  }
  if ('owned' in patch) next.owned = validateIdList(patch.owned, 'owned');
  if ('purchased' in patch) next.purchased = validateIdList(patch.purchased, 'purchased');
  for (const key of ['adoptionOpen', 'lampOn', 'starsOn', 'nightlightOn', 'reducedMotion', 'busy', 'jobsAllowed']) {
    if (key in patch) {
      if (typeof patch[key] !== 'boolean') throw new ProtocolError('INVALID_STATE', `${key} must be boolean`);
      next[key] = patch[key];
    }
  }
  return next;
}

// Ephemeral input progress only. Wallet, reward and completion ownership stay in Flutter.
export function createDishRound() {
  let stage = 'idle';
  let cleaned = 0;
  let waterOn = false;
  const snapshot = () => ({ stage, cleaned, total: 6, waterOn });
  return Object.freeze({
    getState: snapshot,
    start() {
      if (stage !== 'idle') return { ok: false, ...snapshot() };
      stage = 'scrub';
      return { ok: true, ...snapshot() };
    },
    step(kind) {
      if (stage === 'scrub' && kind === 'scrub') {
        cleaned += 1;
        if (cleaned === 6) { stage = 'rinse'; waterOn = true; }
      } else if (stage === 'rinse' && kind === 'rinse') {
        stage = 'water_off';
      } else if (stage === 'water_off' && kind === 'finish') {
        waterOn = false;
        stage = 'ready';
      } else {
        return { ok: false, ...snapshot() };
      }
      return { ok: true, ...snapshot() };
    },
    markRequested() {
      if (stage !== 'ready') return { ok: false, ...snapshot() };
      stage = 'awaiting_ack';
      return { ok: true, ...snapshot() };
    },
    finish(accepted) {
      if (stage !== 'awaiting_ack') return { ok: false, ...snapshot() };
      stage = accepted ? 'complete' : 'rejected';
      return { ok: true, ...snapshot() };
    },
    cancel() {
      if (stage === 'awaiting_ack' || stage === 'complete') return { ok: false, ...snapshot() };
      stage = 'idle';
      cleaned = 0;
      waterOn = false;
      return { ok: true, ...snapshot() };
    },
  });
}

// Ephemeral ordered input for J02-J06. Completion proof is checked again by
// Flutter before the transactional wallet mutation.
export function createJobRound(jobId) {
  const definition = JOB_DEFINITIONS[jobId];
  if (!definition) throw new ProtocolError('INVALID_JOB', 'unknown household job');
  let stage = 'idle';
  let completed = 0;
  const snapshot = () => ({
    jobId,
    room: definition.room,
    title: definition.title,
    stage,
    completed,
    total: definition.steps.length,
    nextStep: definition.steps[completed] || null,
  });
  return Object.freeze({
    getState: snapshot,
    start() {
      if (stage !== 'idle') return { ok: false, ...snapshot() };
      stage = 'active';
      return { ok: true, ...snapshot() };
    },
    step(kind) {
      if (stage !== 'active' || kind !== definition.steps[completed]) {
        return { ok: false, ...snapshot() };
      }
      completed += 1;
      if (completed === definition.steps.length) stage = 'ready';
      return { ok: true, ...snapshot() };
    },
    markRequested() {
      if (stage !== 'ready') return { ok: false, ...snapshot() };
      stage = 'awaiting_ack';
      return { ok: true, ...snapshot() };
    },
    finish(accepted) {
      if (stage !== 'awaiting_ack') return { ok: false, ...snapshot() };
      stage = accepted ? 'complete' : 'rejected';
      return { ok: true, ...snapshot() };
    },
    cancel() {
      if (stage === 'awaiting_ack' || stage === 'complete') return { ok: false, ...snapshot() };
      stage = 'idle';
      completed = 0;
      return { ok: true, ...snapshot() };
    },
  });
}

export function createProtocol(options = {}) {
  const sessionId = options.sessionId || `scene-${randomPart()}`;
  let state = { ...DEFAULT_STATE, owned: [], purchased: [] };
  let pending = null;
  let sequence = 0;
  const resolvedIds = new Set();
  const resolvedOrder = [];

  function snapshot() {
    return { ...state, owned: [...state.owned], purchased: [...state.purchased], viewportInsets: { ...state.viewportInsets } };
  }

  // Sync patches often repeat unchanged values; only real value changes may
  // trigger downstream reactions such as job cancellation or camera refit.
  function sameStateValue(a, b) {
    if (Object.is(a, b)) return true;
    if (Array.isArray(a) && Array.isArray(b)) {
      return a.length === b.length && a.every((v, i) => Object.is(v, b[i]));
    }
    if (a && b && typeof a === 'object' && !Array.isArray(a) && !Array.isArray(b)) {
      const keys = Object.keys(a);
      return keys.length === Object.keys(b).length && keys.every((k) => Object.is(a[k], b[k]));
    }
    return false;
  }

  function setState(patch) {
    const normalized = normalizeStatePatch(patch);
    const previous = snapshot();
    const changed = Object.keys(normalized).filter(
      (key) => !sameStateValue(previous[key], normalized[key]),
    );
    state = { ...state, ...normalized };
    return { previous, state: snapshot(), changed };
  }

  function beginAction(input) {
    if (!input || typeof input !== 'object' || !ACTIONS.has(input.action)) {
      throw new ProtocolError('INVALID_ACTION', 'unknown action');
    }
    if (input.action === 'room' && !ROOMS.has(input.targetRoom)) {
      throw new ProtocolError('INVALID_ACTION', 'room action needs a valid targetRoom');
    }
    if (input.action === 'complete_job' && !JOB_DEFINITIONS[input.jobId]) {
      throw new ProtocolError('INVALID_ACTION', 'complete_job needs a valid jobId');
    }
    if (pending) return { ok: false, reason: 'pending', pending: { ...pending } };
    if (state.busy) return { ok: false, reason: 'state_busy' };
    const id = `${sessionId}:${++sequence}`;
    pending = {
      id,
      action: input.action,
      room: input.room || state.room,
      targetRoom: input.targetRoom,
      jobId: input.jobId,
      source: input.source || 'runtime',
      phase: 'approach',
      createdAt: Date.now(),
    };
    return { ok: true, action: { ...pending } };
  }

  function markRequested(id) {
    if (!pending || pending.id !== id) return false;
    pending.phase = 'awaiting_ack';
    return true;
  }

  function rememberResolved(id) {
    resolvedIds.add(id);
    resolvedOrder.push(id);
    if (resolvedOrder.length > 64) resolvedIds.delete(resolvedOrder.shift());
  }

  function resolveAction(ack) {
    if (!ack || typeof ack !== 'object' || typeof ack.id !== 'string' || typeof ack.accepted !== 'boolean') {
      throw new ProtocolError('INVALID_ACK', 'resolveAction expects {id, accepted}');
    }
    if (resolvedIds.has(ack.id)) return { status: 'duplicate' };
    if (!pending || pending.id !== ack.id) return { status: 'unknown' };
    const action = { ...pending };
    pending = null;
    rememberResolved(ack.id);
    let stateResult = null;
    if (ack.state !== undefined) stateResult = setState(ack.state);
    return {
      status: ack.accepted ? 'accepted' : 'rejected',
      action,
      stateResult,
      message: typeof ack.message === 'string' ? ack.message : null,
    };
  }

  return Object.freeze({
    sessionId,
    getState: snapshot,
    getPending: () => (pending ? { ...pending } : null),
    setState,
    beginAction,
    markRequested,
    resolveAction,
  });
}
