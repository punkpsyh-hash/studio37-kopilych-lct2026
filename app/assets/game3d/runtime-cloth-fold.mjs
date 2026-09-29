const EPSILON = 1e-6;

function clamp01(value) {
  if (!Number.isFinite(value)) throw new TypeError('fold progress must be finite');
  return Math.max(0, Math.min(1, value));
}

function findSingleMesh(root, explicitMesh = null) {
  if (explicitMesh) return explicitMesh;
  const meshes = [];
  root?.traverse?.((object) => {
    if (object?.isMesh && object.geometry?.attributes?.position) meshes.push(object);
  });
  if (meshes.length !== 1) {
    throw new Error(`cloth fold needs exactly one mesh; found ${meshes.length}`);
  }
  return meshes[0];
}

function readVec3Attribute(attribute, label) {
  if (!attribute || attribute.itemSize < 3 || attribute.count < 3) {
    throw new Error(`cloth fold needs a ${label} VEC3 attribute`);
  }
  const values = new Float32Array(attribute.count * 3);
  for (let index = 0; index < attribute.count; index += 1) {
    values[index * 3] = attribute.getX(index);
    values[index * 3 + 1] = attribute.getY(index);
    values[index * 3 + 2] = attribute.getZ(index);
  }
  return values;
}

function boundsForPositions(positions) {
  const minimum = [Infinity, Infinity, Infinity];
  const maximum = [-Infinity, -Infinity, -Infinity];
  for (let offset = 0; offset < positions.length; offset += 3) {
    for (let axis = 0; axis < 3; axis += 1) {
      const value = positions[offset + axis];
      if (!Number.isFinite(value)) throw new Error('cloth fold source contains a non-finite position');
      minimum[axis] = Math.min(minimum[axis], value);
      maximum[axis] = Math.max(maximum[axis], value);
    }
  }
  return {
    min: minimum,
    max: maximum,
    size: maximum.map((value, axis) => value - minimum[axis]),
    center: maximum.map((value, axis) => (value + minimum[axis]) * 0.5),
  };
}

function normalizeNormals(normals) {
  for (let offset = 0; offset < normals.length; offset += 3) {
    const x = normals[offset];
    const y = normals[offset + 1];
    const z = normals[offset + 2];
    const length = Math.hypot(x, y, z);
    if (!Number.isFinite(length) || length < EPSILON) {
      throw new Error(`cloth fold source contains an invalid normal at vertex ${offset / 3}`);
    }
    normals[offset] = x / length;
    normals[offset + 1] = y / length;
    normals[offset + 2] = z / length;
  }
}

function axisIndex(axis) {
  if (axis === 'x') return 0;
  if (axis === 'z') return 2;
  throw new Error(`cloth fold axis must be x or z; got ${axis}`);
}

function smoothstep(value) {
  const t = Math.max(0, Math.min(1, value));
  return t * t * (3 - 2 * t);
}

function smoothstepDerivative(value) {
  if (value <= 0 || value >= 1) return 0;
  return 6 * value * (1 - value);
}

function estimatePlyThickness(positions, bounds) {
  const cellsPerAxis = 32;
  const cellCount = cellsPerAxis * cellsPerAxis;
  const low = new Float32Array(cellCount);
  const high = new Float32Array(cellCount);
  const counts = new Uint16Array(cellCount);
  low.fill(Infinity);
  high.fill(-Infinity);
  const sizeX = Math.max(bounds.size[0], EPSILON);
  const sizeZ = Math.max(bounds.size[2], EPSILON);
  for (let offset = 0; offset < positions.length; offset += 3) {
    const cellX = Math.min(cellsPerAxis - 1,
      Math.floor((positions[offset] - bounds.min[0]) / sizeX * cellsPerAxis));
    const cellZ = Math.min(cellsPerAxis - 1,
      Math.floor((positions[offset + 2] - bounds.min[2]) / sizeZ * cellsPerAxis));
    const cell = cellZ * cellsPerAxis + cellX;
    low[cell] = Math.min(low[cell], positions[offset + 1]);
    high[cell] = Math.max(high[cell], positions[offset + 1]);
    counts[cell] += 1;
  }
  const localSpans = [];
  for (let cell = 0; cell < cellCount; cell += 1) {
    if (counts[cell] >= 4 && Number.isFinite(low[cell]) && Number.isFinite(high[cell])) {
      localSpans.push(high[cell] - low[cell]);
    }
  }
  localSpans.sort((left, right) => left - right);
  const planarSize = Math.min(bounds.size[0], bounds.size[2]);
  const sampled = localSpans.length >= 16
    ? localSpans[Math.floor((localSpans.length - 1) * 0.6)]
    : bounds.size[1] * 0.25;
  return Math.max(planarSize * 0.012, Math.min(sampled, planarSize * 0.08));
}

function normalizeStep(step, index, sourceBounds, plyThickness) {
  const axis = step?.axis || (index === 0 ? 'z' : 'x');
  const coordinate = axisIndex(axis);
  const size = sourceBounds.size[coordinate];
  const side = step?.side === -1 ? -1 : 1;
  const crease = Number.isFinite(step?.crease) ? step.crease : sourceBounds.center[coordinate];
  const creaseWidth = Number.isFinite(step?.creaseWidth)
    ? step.creaseWidth : Math.max(size * 0.075, EPSILON);
  const layerGap = Number.isFinite(step?.layerGap)
    ? step.layerGap : Math.max(plyThickness * 0.12, size * 0.004);
  const layerSeparation = Number.isFinite(step?.layerSeparation)
    ? step.layerSeparation : plyThickness * (2 ** index) + layerGap;
  if (!(creaseWidth > EPSILON) || !(layerGap >= 0) || !(layerSeparation >= 0)) {
    throw new Error('cloth fold dimensions must be positive');
  }
  return Object.freeze({
    axis, coordinate, side, crease, creaseWidth, layerGap, layerSeparation,
  });
}

function applyFold(inputPositions, inputNormals, outputPositions, outputNormals, step, progress) {
  const theta = Math.PI * progress;
  if (theta <= EPSILON) {
    outputPositions.set(inputPositions);
    outputNormals.set(inputNormals);
    return;
  }

  let lowY = Infinity;
  let highY = -Infinity;
  for (let offset = 1; offset < inputPositions.length; offset += 3) {
    lowY = Math.min(lowY, inputPositions[offset]);
    highY = Math.max(highY, inputPositions[offset]);
  }
  const middleY = (lowY + highY) * 0.5;
  const fullArcHeight = step.creaseWidth * 2 / Math.PI;
  const fullLayerLift = Math.max(0, step.layerSeparation - fullArcHeight);
  const layerLift = fullLayerLift * Math.sin(theta * 0.5) ** 2;

  for (let offset = 0; offset < inputPositions.length; offset += 3) {
    const coordinate = step.coordinate;
    const q = inputPositions[offset + coordinate];
    const distance = step.side * (q - step.crease);
    if (distance <= 0) {
      outputPositions[offset] = inputPositions[offset];
      outputPositions[offset + 1] = inputPositions[offset + 1];
      outputPositions[offset + 2] = inputPositions[offset + 2];
      outputNormals[offset] = inputNormals[offset];
      outputNormals[offset + 1] = inputNormals[offset + 1];
      outputNormals[offset + 2] = inputNormals[offset + 2];
      continue;
    }

    const withinCrease = distance < step.creaseWidth;
    const creaseUnit = Math.min(1, distance / step.creaseWidth);
    const localAngle = withinCrease ? theta * creaseUnit : theta;
    let centerQ;
    let centerY;
    let derivativeQ;
    let derivativeY;
    if (withinCrease) {
      const radius = step.creaseWidth / theta;
      centerQ = radius * Math.sin(localAngle);
      centerY = radius * (1 - Math.cos(localAngle));
      derivativeQ = Math.cos(localAngle);
      derivativeY = Math.sin(localAngle);
    } else {
      const radius = step.creaseWidth / theta;
      const bandQ = radius * Math.sin(theta);
      const bandY = radius * (1 - Math.cos(theta));
      const tail = distance - step.creaseWidth;
      centerQ = bandQ + tail * Math.cos(theta);
      centerY = bandY + tail * Math.sin(theta);
      derivativeQ = Math.cos(theta);
      derivativeY = Math.sin(theta);
    }

    const activation = smoothstep(creaseUnit);
    centerY += layerLift * activation;
    derivativeY += layerLift * smoothstepDerivative(creaseUnit) / step.creaseWidth;
    const tangentAngle = Math.atan2(derivativeY, derivativeQ);
    const sin = Math.sin(tangentAngle);
    const cos = Math.cos(tangentAngle);
    const height = inputPositions[offset + 1] - middleY;
    const foldedQ = centerQ - height * sin;
    const foldedY = middleY + centerY + height * cos;

    outputPositions[offset] = inputPositions[offset];
    outputPositions[offset + 1] = foldedY;
    outputPositions[offset + 2] = inputPositions[offset + 2];
    outputPositions[offset + coordinate] = step.crease + step.side * foldedQ;

    const normalQ = step.side * inputNormals[offset + coordinate];
    const normalY = inputNormals[offset + 1];
    const foldedNormalQ = normalQ * cos - normalY * sin;
    const foldedNormalY = normalQ * sin + normalY * cos;
    outputNormals[offset] = inputNormals[offset];
    outputNormals[offset + 1] = foldedNormalY;
    outputNormals[offset + 2] = inputNormals[offset + 2];
    outputNormals[offset + coordinate] = step.side * foldedNormalQ;
    const normalLength = Math.hypot(
      outputNormals[offset], outputNormals[offset + 1], outputNormals[offset + 2]);
    if (!Number.isFinite(normalLength) || normalLength < EPSILON) {
      throw new Error(`cloth fold produced an invalid normal at vertex ${offset / 3}`);
    }
    outputNormals[offset] /= normalLength;
    outputNormals[offset + 1] /= normalLength;
    outputNormals[offset + 2] /= normalLength;
  }
}

function geometryCounts(geometry) {
  return {
    vertices: geometry.attributes.position.count,
    indices: geometry.index?.count || 0,
    uv: geometry.attributes.uv?.count || 0,
    groups: geometry.groups.length,
  };
}

/**
 * CPU fold controller for the existing generated towel mesh.
 *
 * The controller preserves the original geometry, material, topology and UVs.
 * Only cloned POSITION/NORMAL buffers are updated.
 */
export function createClothFold({ THREE, root, mesh: explicitMesh = null, steps = null } = {}) {
  if (!THREE?.BufferAttribute) throw new Error('createClothFold needs the pinned THREE namespace');
  const mesh = findSingleMesh(root, explicitMesh);
  const sourceGeometry = mesh.geometry;
  const sourcePosition = readVec3Attribute(sourceGeometry.attributes.position, 'POSITION');
  const sourceNormal = readVec3Attribute(sourceGeometry.attributes.normal, 'NORMAL');
  normalizeNormals(sourceNormal);
  if (!sourceGeometry.attributes.uv || sourceGeometry.attributes.uv.count !== sourceGeometry.attributes.position.count) {
    throw new Error('cloth fold needs one TEXCOORD_0 value per source vertex');
  }
  const sourceBounds = boundsForPositions(sourcePosition);
  const planarSize = Math.min(sourceBounds.size[0], sourceBounds.size[2]);
  if (!(sourceBounds.size[1] < planarSize * 0.35)) {
    throw new Error(`cloth fold expected local Y thickness; sizes=${sourceBounds.size.join(',')}`);
  }

  const estimatedPlyThickness = estimatePlyThickness(sourcePosition, sourceBounds);
  const definitions = (steps || [{ axis: 'z', side: 1 }, { axis: 'x', side: 1 }])
    .map((step, index) => normalizeStep(step, index, sourceBounds, estimatedPlyThickness));
  if (definitions.length !== 2) throw new Error('cloth fold currently requires exactly two fold steps');

  const derivative = sourceGeometry.clone();
  const livePosition = new Float32Array(sourcePosition);
  const liveNormal = new Float32Array(sourceNormal);
  const positionAttribute = new THREE.BufferAttribute(livePosition, 3);
  const normalAttribute = new THREE.BufferAttribute(liveNormal, 3);
  positionAttribute.setUsage?.(THREE.DynamicDrawUsage);
  normalAttribute.setUsage?.(THREE.DynamicDrawUsage);
  derivative.setAttribute('position', positionAttribute);
  derivative.setAttribute('normal', normalAttribute);
  derivative.computeBoundingBox();
  derivative.computeBoundingSphere();
  mesh.geometry = derivative;

  const scratchPositions = [new Float32Array(sourcePosition.length), new Float32Array(sourcePosition.length)];
  const scratchNormals = [new Float32Array(sourceNormal.length), new Float32Array(sourceNormal.length)];
  const progresses = [0, 0];
  const sourceCounts = geometryCounts(sourceGeometry);
  let disposed = false;

  function assertAlive() {
    if (disposed) throw new Error('cloth fold controller is disposed');
  }

  function renderPose() {
    scratchPositions[0].set(sourcePosition);
    scratchNormals[0].set(sourceNormal);
    let active = 0;
    for (let index = 0; index < definitions.length; index += 1) {
      const progress = progresses[index];
      if (progress <= 0) continue;
      const next = 1 - active;
      applyFold(
        scratchPositions[active], scratchNormals[active],
        scratchPositions[next], scratchNormals[next], definitions[index], progress,
      );
      active = next;
    }
    livePosition.set(scratchPositions[active]);
    liveNormal.set(scratchNormals[active]);
    positionAttribute.needsUpdate = true;
    normalAttribute.needsUpdate = true;
    derivative.computeBoundingBox();
    derivative.computeBoundingSphere();
  }

  function setProgresses(nextProgresses) {
    assertAlive();
    if (!Array.isArray(nextProgresses) || nextProgresses.length !== 2) {
      throw new TypeError('setProgresses needs [firstFold, secondFold]');
    }
    const next = nextProgresses.map(clamp01);
    if (next[1] > 0 && next[0] < 1 - EPSILON) {
      throw new Error('second fold cannot start before the first fold is complete');
    }
    progresses[0] = next[0];
    progresses[1] = next[1];
    renderPose();
    return diagnostics();
  }

  function setPose(stepIndex, progress) {
    assertAlive();
    if (!Number.isInteger(stepIndex) || stepIndex < 0 || stepIndex >= definitions.length) {
      throw new RangeError(`fold step index must be 0 or 1; got ${stepIndex}`);
    }
    const value = clamp01(progress);
    return stepIndex === 0 ? setProgresses([value, 0]) : setProgresses([1, value]);
  }

  function reset() {
    return setProgresses([0, 0]);
  }

  function diagnostics() {
    const bounds = derivative.boundingBox;
    const currentCounts = geometryCounts(derivative);
    return {
      progresses: [...progresses],
      vertices: currentCounts.vertices,
      indices: currentCounts.indices,
      uv: currentCounts.uv,
      groups: currentCounts.groups,
      topologyPreserved: currentCounts.vertices === sourceCounts.vertices
        && currentCounts.indices === sourceCounts.indices && currentCounts.groups === sourceCounts.groups,
      uvPreserved: currentCounts.uv === sourceCounts.uv,
      sourceSize: [...sourceBounds.size],
      estimatedPlyThickness,
      bounds: bounds ? {
        min: bounds.min.toArray(), max: bounds.max.toArray(),
        size: bounds.getSize(new THREE.Vector3()).toArray(),
      } : null,
      steps: definitions.map((step) => ({ ...step })),
      disposed,
    };
  }

  function dispose() {
    if (disposed) return;
    if (mesh.geometry === derivative) mesh.geometry = sourceGeometry;
    derivative.dispose();
    disposed = true;
  }

  return Object.freeze({ mesh, geometry: derivative, setPose, setProgresses, reset, diagnostics, dispose });
}
