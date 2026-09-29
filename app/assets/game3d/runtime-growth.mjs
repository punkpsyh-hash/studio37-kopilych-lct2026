const STAGE_WEIGHTS = Object.freeze({
  1: Object.freeze([0, 0]),
  2: Object.freeze([1, 0]),
  3: Object.freeze([0, 1]),
});

/**
 * Owns only the two authored growth lanes. Animation clips remain the owner of
 * blink, RestFold, RestTransfer and every other morph influence.
 */
export function createPetGrowthController(root, {
  initialStage = 1,
  reducedMotion = false,
  durationSeconds = 0.6,
} = {}) {
  const lanes = [];
  const incomplete = [];
  root?.traverse((object) => {
    if (!object.isSkinnedMesh || !object.morphTargetInfluences || !object.morphTargetDictionary) return;
    const stage2 = object.morphTargetDictionary.GrowthStage2;
    const stage3 = object.morphTargetDictionary.GrowthStage3;
    if (Number.isInteger(stage2) && Number.isInteger(stage3)) {
      lanes.push({ object, name: object.name, stage2, stage3 });
    } else if (Number.isInteger(stage2) || Number.isInteger(stage3)) {
      incomplete.push({ name: object.name, stage2: Number.isInteger(stage2), stage3: Number.isInteger(stage3) });
    }
  });
  const available = lanes.length > 0 && incomplete.length === 0;
  let stage = STAGE_WEIGHTS[initialStage] ? initialStage : 1;
  let current = [...STAGE_WEIGHTS[stage]];
  let start = [...current];
  let target = [...current];
  let elapsed = durationSeconds;
  let transitioning = false;

  const apply = () => {
    if (!available) return false;
    for (const lane of lanes) {
      lane.object.morphTargetInfluences[lane.stage2] = current[0];
      lane.object.morphTargetInfluences[lane.stage3] = current[1];
    }
    return true;
  };

  const setStage = (nextStage, { snap = false, reducedMotion: nextReducedMotion = reducedMotion } = {}) => {
    if (!STAGE_WEIGHTS[nextStage]) return { ok: false, reason: 'invalid_stage' };
    stage = nextStage;
    start = [...current];
    target = [...STAGE_WEIGHTS[nextStage]];
    elapsed = 0;
    transitioning = available && !snap && !nextReducedMotion && durationSeconds > 0
      && (Math.abs(start[0] - target[0]) > 1e-6 || Math.abs(start[1] - target[1]) > 1e-6);
    if (!transitioning) current = [...target];
    apply();
    return { ok: available, reason: available ? null : 'growth_morphs_unavailable', stage, transitioning };
  };

  const update = (deltaSeconds = 0) => {
    if (transitioning) {
      elapsed = Math.min(durationSeconds, elapsed + Math.max(0, deltaSeconds));
      const t = durationSeconds > 0 ? elapsed / durationSeconds : 1;
      const eased = t * t * (3 - 2 * t);
      current[0] = start[0] + (target[0] - start[0]) * eased;
      current[1] = start[1] + (target[1] - start[1]) * eased;
      if (t >= 1) transitioning = false;
    }
    apply();
  };

  const diagnostics = () => ({
    available,
    stage,
    current: current.map((value) => +value.toFixed(5)),
    target: target.map((value) => +value.toFixed(5)),
    transitioning,
    durationSeconds,
    lanes: lanes.map(({ name, stage2, stage3 }) => ({ name, GrowthStage2: stage2, GrowthStage3: stage3 })),
    incomplete,
  });

  setStage(stage, { snap: true });
  return { available, apply, update, setStage, diagnostics };
}
