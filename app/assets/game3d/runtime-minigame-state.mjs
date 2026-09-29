function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function distanceToSegment(point, from, to) {
  const dx = to.x - from.x;
  const dz = to.z - from.z;
  const lengthSquared = dx * dx + dz * dz;
  if (lengthSquared < 1e-8) return Math.hypot(point.x - from.x, point.z - from.z);
  const t = clamp(((point.x - from.x) * dx + (point.z - from.z) * dz) / lengthSquared, 0, 1);
  return Math.hypot(point.x - (from.x + dx * t), point.z - (from.z + dz * t));
}

export function createCoverageField({ center, radius, resolution = 7, threshold = 0.7 } = {}) {
  if (!center || !Number.isFinite(center.x) || !Number.isFinite(center.z) ||
      !Number.isFinite(radius) || radius <= 0 || !Number.isInteger(resolution) || resolution < 3) {
    throw new TypeError('createCoverageField requires a finite center, positive radius and resolution >= 3');
  }
  const cells = [];
  for (let row = 0; row < resolution; row += 1) {
    for (let column = 0; column < resolution; column += 1) {
      const x = ((column + 0.5) / resolution) * 2 - 1;
      const z = ((row + 0.5) / resolution) * 2 - 1;
      if (x * x + z * z <= 1) cells.push({ x: center.x + x * radius, z: center.z + z * radius, hit: false });
    }
  }
  let hitCount = 0;
  const coverage = () => cells.length ? hitCount / cells.length : 0;
  return Object.freeze({
    center: Object.freeze({ x: center.x, z: center.z }),
    radius,
    threshold,
    sampleSegment(from, to, brushRadius) {
      if (!from || !to || !Number.isFinite(brushRadius) || brushRadius <= 0) return coverage();
      for (const cell of cells) {
        if (!cell.hit && distanceToSegment(cell, from, to) <= brushRadius) {
          cell.hit = true;
          hitCount += 1;
        }
      }
      return coverage();
    },
    coverage,
    complete: () => coverage() >= threshold,
    reset() {
      for (const cell of cells) cell.hit = false;
      hitCount = 0;
    },
    diagnostics: () => ({ coverage: coverage(), hit: hitCount, total: cells.length, threshold }),
  });
}

export function pushDustPile({ position, from, to, intake, contactRadius = 0.11,
  captureRadius = 0.1, requiredDirectionDot = 0.2, maxStep = 0.075, bounds } = {}) {
  if (![position, from, to, intake].every((point) => point && Number.isFinite(point.x) && Number.isFinite(point.z))) {
    return { moved: false, captured: false, directionDot: -1 };
  }
  const strokeX = to.x - from.x;
  const strokeZ = to.z - from.z;
  const strokeLength = Math.hypot(strokeX, strokeZ);
  const targetX = intake.x - position.x;
  const targetZ = intake.z - position.z;
  const targetLength = Math.hypot(targetX, targetZ);
  if (targetLength <= captureRadius) return { moved: false, captured: true, directionDot: 1 };
  if (strokeLength < 0.006 || distanceToSegment(position, from, to) > contactRadius) {
    return { moved: false, captured: false, directionDot: -1 };
  }
  const directionDot = (strokeX * targetX + strokeZ * targetZ) / (strokeLength * targetLength);
  if (directionDot < requiredDirectionDot) return { moved: false, captured: false, directionDot };
  const step = Math.min(maxStep, strokeLength * 0.82, targetLength);
  // Bias the child's actual stroke toward the pan so a slightly imperfect
  // sweep remains expressive without letting sideways rubbing collect dust.
  const strokeWeight = 0.62;
  let moveX = (strokeX / strokeLength) * strokeWeight + (targetX / targetLength) * (1 - strokeWeight);
  let moveZ = (strokeZ / strokeLength) * strokeWeight + (targetZ / targetLength) * (1 - strokeWeight);
  const moveLength = Math.hypot(moveX, moveZ) || 1;
  moveX = moveX / moveLength * step;
  moveZ = moveZ / moveLength * step;
  position.x += moveX;
  position.z += moveZ;
  if (bounds) {
    position.x = clamp(position.x, bounds.minX, bounds.maxX);
    position.z = clamp(position.z, bounds.minZ, bounds.maxZ);
  }
  const remaining = Math.hypot(intake.x - position.x, intake.z - position.z);
  if (remaining <= captureRadius) {
    position.x = intake.x;
    position.z = intake.z;
    return { moved: true, captured: true, directionDot };
  }
  return { moved: true, captured: false, directionDot };
}
