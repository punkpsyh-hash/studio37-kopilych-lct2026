const FOAM_CAPACITY = 96;
const BUBBLE_CAPACITY = 24;
const SPARKLE_CAPACITY = 12;
const FOAM_CENTER_LIMIT = 0.84;

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function finiteVector(THREE, value, fallback) {
  if (value?.isVector3 && [value.x, value.y, value.z].every(Number.isFinite)) {
    return value.clone();
  }
  if (Array.isArray(value) && value.length >= 3 && value.slice(0, 3).every(Number.isFinite)) {
    return new THREE.Vector3(value[0], value[1], value[2]);
  }
  return fallback.clone();
}

function starGeometry(THREE) {
  const vertices = [];
  const points = [];
  for (let index = 0; index < 8; index += 1) {
    const angle = index * Math.PI / 4;
    const radius = index % 2 === 0 ? 1 : 0.28;
    points.push([Math.cos(angle) * radius, 0, Math.sin(angle) * radius]);
  }
  for (let index = 0; index < points.length; index += 1) {
    vertices.push(0, 0, 0, ...points[index], ...points[(index + 1) % points.length]);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
  geometry.computeVertexNormals();
  return geometry;
}

export function createDishFoam({ THREE, scene, reducedMotion = false } = {}) {
  if (!THREE?.Group || !THREE?.InstancedMesh || !THREE?.ShaderMaterial || !scene?.add) {
    throw new TypeError('createDishFoam requires THREE and a scene-like parent');
  }

  const root = new THREE.Group();
  root.name = 'VFX__dish_foam';
  root.visible = false;
  scene.add(root);

  const foamMaterial = new THREE.MeshBasicMaterial({
    color: 0xfffdf6,
    transparent: true,
    opacity: 0.72,
    depthWrite: false,
    toneMapped: false,
  });
  const bubbleMaterial = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    toneMapped: false,
    vertexShader: `
      varying vec3 vNormal;
      varying vec3 vViewDirection;
      void main() {
        vec4 localPosition = instanceMatrix * vec4(position, 1.0);
        vec4 viewPosition = modelViewMatrix * localPosition;
        vNormal = normalize(normalMatrix * mat3(instanceMatrix) * normal);
        vViewDirection = normalize(-viewPosition.xyz);
        gl_Position = projectionMatrix * viewPosition;
      }
    `,
    fragmentShader: `
      varying vec3 vNormal;
      varying vec3 vViewDirection;
      void main() {
        vec3 normal = normalize(vNormal);
        vec3 viewDirection = normalize(vViewDirection);
        float edge = 1.0 - abs(dot(normal, viewDirection));
        float rim = smoothstep(0.22, 0.86, edge);
        float glint = pow(max(dot(normal, normalize(vec3(-0.35, 0.82, 0.45))), 0.0), 28.0);
        vec3 cool = vec3(0.80, 0.95, 1.0);
        vec3 warm = vec3(1.0, 0.88, 0.98);
        vec3 tint = mix(cool, warm, 0.5 + 0.5 * normal.x);
        vec3 color = mix(tint, vec3(1.0), 0.72 + glint * 0.28);
        float alpha = 0.018 + rim * 0.48 + glint * 0.38;
        gl_FragColor = vec4(color, alpha);
      }
    `,
  });
  const sparkleMaterial = new THREE.MeshBasicMaterial({
    color: 0xfff3a8,
    transparent: true,
    opacity: 0.9,
    depthWrite: false,
    side: THREE.DoubleSide,
    toneMapped: false,
  });
  const foamGeometry = new THREE.SphereGeometry(1, 14, 8);
  const bubbleGeometry = new THREE.SphereGeometry(1, 14, 10);
  const sparkleGeometry = starGeometry(THREE);
  const foam = new THREE.InstancedMesh(foamGeometry, foamMaterial, FOAM_CAPACITY);
  const bubbles = new THREE.InstancedMesh(bubbleGeometry, bubbleMaterial, BUBBLE_CAPACITY);
  const sparkles = new THREE.InstancedMesh(sparkleGeometry, sparkleMaterial, SPARKLE_CAPACITY);
  foam.name = 'VFX__dish_foam_surface';
  bubbles.name = 'VFX__dish_bubbles';
  sparkles.name = 'VFX__dish_sparkles';
  foam.renderOrder = 6;
  bubbles.renderOrder = 7;
  sparkles.renderOrder = 8;
  foam.frustumCulled = false;
  bubbles.frustumCulled = false;
  sparkles.frustumCulled = false;
  foam.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  bubbles.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  sparkles.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  root.add(foam, bubbles, sparkles);

  const hiddenMatrix = new THREE.Matrix4().makeScale(0, 0, 0);
  const matrix = new THREE.Matrix4();
  const quaternion = new THREE.Quaternion();
  const identityQuaternion = new THREE.Quaternion();
  const center = new THREE.Vector3();
  const normal = new THREE.Vector3(0, 1, 0);
  const tangentA = new THREE.Vector3(1, 0, 0);
  const tangentB = new THREE.Vector3(0, 0, 1);
  const temp = new THREE.Vector3();
  const scale = new THREE.Vector3();
  const up = new THREE.Vector3(0, 1, 0);
  const foamEntries = Array.from({ length: FOAM_CAPACITY }, () => ({ active: false }));
  const bubbleEntries = Array.from({ length: BUBBLE_CAPACITY }, () => ({ active: false }));
  const sparkleEntries = Array.from({ length: SPARKLE_CAPACITY }, () => ({ active: false }));
  const foamColors = [0xfffdf6, 0xffffff, 0xf8fcff, 0xfffbf5];
  const bubbleColors = [0xe8f9ff, 0xfbeeff, 0xeffff2, 0xfffae8];
  const splashColors = [0xe4f9ff, 0xf2fdff, 0xdcf5ff];
  let surfaceRadius = 0.31;
  let surfaceReady = false;
  let foamCount = 0;
  let foamCursor = 0;
  let foamReuses = 0;
  let bubbleCursor = 0;
  let sparkleCursor = 0;
  let scrubCount = 0;
  let scrubSamples = 0;
  let rinseSamples = 0;
  let foamPeak = 0;
  let paused = false;
  let lowMotion = Boolean(reducedMotion);
  let lastScrub = null;
  let scrubBubbleClock = 1;
  let rinseBubbleClock = 1;
  let randomState = 0x37c0ffee;

  function random() {
    randomState = (Math.imul(randomState, 1664525) + 1013904223) >>> 0;
    return randomState / 0x100000000;
  }

  function markMatrices() {
    foam.instanceMatrix.needsUpdate = true;
    bubbles.instanceMatrix.needsUpdate = true;
    sparkles.instanceMatrix.needsUpdate = true;
    if (foam.instanceColor) foam.instanceColor.needsUpdate = true;
    if (bubbles.instanceColor) bubbles.instanceColor.needsUpdate = true;
    if (sparkles.instanceColor) sparkles.instanceColor.needsUpdate = true;
  }

  function hideAllInstances(mesh, entries) {
    entries.forEach((entry, index) => {
      entry.active = false;
      mesh.setMatrixAt(index, hiddenMatrix);
    });
    mesh.instanceMatrix.needsUpdate = true;
  }

  function rebuildBasis() {
    const reference = Math.abs(normal.x) < 0.85
      ? new THREE.Vector3(1, 0, 0)
      : new THREE.Vector3(0, 0, 1);
    tangentA.crossVectors(reference, normal).normalize();
    tangentB.crossVectors(normal, tangentA).normalize();
    quaternion.setFromUnitVectors(up, normal);
  }

  function surfaceCoordinates(rawPoint) {
    const point = finiteVector(THREE, rawPoint, center);
    temp.copy(point).sub(center);
    temp.addScaledVector(normal, -temp.dot(normal));
    const length = temp.length();
    if (length > surfaceRadius * FOAM_CENTER_LIMIT) {
      temp.multiplyScalar((surfaceRadius * FOAM_CENTER_LIMIT) / length);
    }
    return {
      u: temp.dot(tangentA) / surfaceRadius,
      v: temp.dot(tangentB) / surfaceRadius,
      position: point.copy(center).add(temp).addScaledVector(normal, 0.003),
    };
  }

  function surfaceWorld(u, v, height = 0.003) {
    return center.clone()
      .addScaledVector(tangentA, u * surfaceRadius)
      .addScaledVector(tangentB, v * surfaceRadius)
      .addScaledVector(normal, height);
  }

  function setFoamMatrix(index) {
    const entry = foamEntries[index];
    if (!entry.active) {
      foam.setMatrixAt(index, hiddenMatrix);
      return;
    }
    const fadeScale = entry.fadeDuration > 0
      ? clamp(entry.fadeRemaining / entry.fadeDuration, 0, 1)
      : 1;
    const position = surfaceWorld(entry.u, entry.v, 0.0025 + (index % 7) * 0.00004);
    const size = entry.size * fadeScale;
    scale.set(size * 0.92, Math.max(0.0006, size * 0.13), size);
    matrix.compose(position, quaternion, scale);
    foam.setMatrixAt(index, matrix);
  }

  function setFoamInstance(index, u, v, size, color) {
    foamEntries[index] = {
      active: true,
      u,
      v,
      size,
      fadeRemaining: 0,
      fadeDuration: 0,
    };
    setFoamMatrix(index);
    foam.setColorAt(index, new THREE.Color(color));
  }

  function nextFoamIndex() {
    for (let offset = 0; offset < FOAM_CAPACITY; offset += 1) {
      const index = (foamCursor + offset) % FOAM_CAPACITY;
      if (!foamEntries[index].active) {
        foamCursor = (index + 1) % FOAM_CAPACITY;
        return { index, reused: false };
      }
    }
    const index = foamCursor;
    foamCursor = (foamCursor + 1) % FOAM_CAPACITY;
    foamReuses += 1;
    return { index, reused: true };
  }

  function activateSparkle(
    position,
    color = 0xfff3a8,
    sparkleSize = lowMotion ? 0.004 : 0.006,
  ) {
    const index = sparkleCursor++ % SPARKLE_CAPACITY;
    sparkleEntries[index] = {
      active: true,
      age: 0,
      lifetime: lowMotion ? 0.16 : 0.32,
      position: position.clone(),
      size: sparkleSize,
    };
    sparkles.setColorAt(index, new THREE.Color(color));
  }

  function activateBubble(position, { splash = false, intensity = 1 } = {}) {
    const index = bubbleCursor++ % BUBBLE_CAPACITY;
    // Final pulsing diameter stays below 15 mm on a 28 cm plate.
    const size = clamp((splash ? 0.0024 : 0.0028) * (0.65 + random() * 0.7) * intensity, 0.001, 0.006);
    const sideways = surfaceRadius * (splash ? 0.8 : 0.28);
    bubbleEntries[index] = {
      active: true,
      age: 0,
      lifetime: lowMotion ? 0.22 : splash ? 0.58 + random() * 0.22 : 0.72 + random() * 0.42,
      position: position.clone(),
      velocity: normal.clone().multiplyScalar(lowMotion ? 0.035 : splash ? 0.18 : 0.09 + random() * 0.09)
        .addScaledVector(tangentA, (random() - 0.5) * sideways)
        .addScaledVector(tangentB, (random() - 0.5) * sideways),
      size,
      splash,
    };
    const palette = splash ? splashColors : bubbleColors;
    bubbles.setColorAt(index, new THREE.Color(palette[index % palette.length]));
  }

  function setSurface({ center: nextCenter, normal: nextNormal, radius } = {}) {
    center.copy(finiteVector(THREE, nextCenter, center));
    normal.copy(finiteVector(THREE, nextNormal, up));
    if (normal.lengthSq() < 1e-6) normal.copy(up);
    normal.normalize();
    surfaceRadius = Number.isFinite(radius) ? clamp(radius, 0.08, 1.2) : 0.31;
    rebuildBasis();
    surfaceReady = true;
    foamEntries.forEach((entry, index) => {
      if (entry.active) setFoamMatrix(index);
    });
    foam.instanceMatrix.needsUpdate = true;
    return diagnostics();
  }

  function scrubAt(worldPoint, intensity = 1, deltaSeconds = 1 / 60, dirtColor = null) {
    if (!surfaceReady) return { ok: false, reason: 'surface_unset' };
    if (paused) return { ok: false, reason: 'paused' };
    const strength = clamp(Number.isFinite(intensity) ? intensity : 1, 0.25, 1.5);
    const dt = clamp(Number.isFinite(deltaSeconds) ? deltaSeconds : 1 / 60, 0, 0.1);
    const contact = surfaceCoordinates(worldPoint);
    scrubSamples += 1;
    scrubBubbleClock += dt;
    const distance = lastScrub
      ? Math.hypot(contact.u - lastScrub.u, contact.v - lastScrub.v) * surfaceRadius
      : Infinity;
    const spacing = surfaceRadius * (lowMotion ? 0.10 : 0.065);
    const steps = lastScrub && Number.isFinite(distance)
      ? clamp(Math.ceil(distance / spacing), 1, 5)
      : 1;
    const moving = Number.isFinite(distance) && distance > 0.0008;
    const shouldDeposit = !lastScrub || (moving && distance >= spacing * 0.42);
    let deposited = 0;
    if (shouldDeposit) {
      for (let item = 1; item <= steps; item += 1) {
        const t = item / steps;
        const baseU = lastScrub ? lastScrub.u + (contact.u - lastScrub.u) * t : contact.u;
        const baseV = lastScrub ? lastScrub.v + (contact.v - lastScrub.v) * t : contact.v;
        const angle = random() * Math.PI * 2;
        const spread = 0.018 + random() * 0.045;
        const u = baseU + Math.cos(angle) * spread;
        const v = baseV + Math.sin(angle) * spread;
        const radial = Math.hypot(u, v);
        const maxRadius = FOAM_CENTER_LIMIT;
        const boundedU = radial > maxRadius ? u * maxRadius / radial : u;
        const boundedV = radial > maxRadius ? v * maxRadius / radial : v;
        const size = clamp(
          surfaceRadius * (0.027 + random() * 0.024) * strength,
          0.0035,
          0.0075,
        );
        const slot = nextFoamIndex();
        setFoamInstance(
          slot.index,
          boundedU,
          boundedV,
          size,
          Number.isInteger(dirtColor)
            ? new THREE.Color(foamColors[slot.index % foamColors.length]).lerp(new THREE.Color(dirtColor), 0.16)
            : foamColors[slot.index % foamColors.length],
        );
        if (!slot.reused) foamCount += 1;
        deposited += 1;
      }
    }
    const bubbleInterval = lowMotion ? 0.3 : 0.14;
    if (moving && scrubBubbleClock >= bubbleInterval) {
      const bubbleCount = 1;
      const du = contact.u - lastScrub.u;
      const dv = contact.v - lastScrub.v;
      const length = Math.hypot(du, dv);
      const trail = Math.min(0.018 / surfaceRadius, length);
      const trailingEdge = surfaceWorld(contact.u - du / length * trail, contact.v - dv / length * trail);
      for (let item = 0; item < bubbleCount; item += 1) {
        activateBubble(trailingEdge, { intensity: strength });
      }
      scrubBubbleClock = 0;
    }
    if (deposited > 0 && !lowMotion && scrubCount % 12 === 0) {
      activateSparkle(contact.position, bubbleColors[scrubCount % bubbleColors.length]);
    }
    scrubCount += 1;
    foamPeak = Math.max(foamPeak, foamCount);
    lastScrub = { u: contact.u, v: contact.v };
    foamMaterial.opacity = 0.72;
    root.visible = true;
    markMatrices();
    return { ok: true, deposited, foamCount, activeBubbles: activeCount(bubbleEntries) };
  }

  function rinseAt(worldPoint, intensity = 1, deltaSeconds = 1 / 60) {
    if (!surfaceReady) return { ok: false, reason: 'surface_unset' };
    if (paused) return { ok: false, reason: 'paused' };
    const strength = clamp(Number.isFinite(intensity) ? intensity : 1, 0.25, 1.5);
    const dt = clamp(Number.isFinite(deltaSeconds) ? deltaSeconds : 1 / 60, 0, 0.1);
    const contact = surfaceCoordinates(worldPoint);
    const washRadius = (lowMotion ? 0.24 : 0.20) * strength;
    let clearing = 0;
    foamEntries.forEach((entry) => {
      if (!entry.active || entry.fadeDuration > 0) return;
      if (Math.hypot(entry.u - contact.u, entry.v - contact.v) <= washRadius) {
        entry.fadeDuration = lowMotion ? 0.08 : 0.22;
        entry.fadeRemaining = entry.fadeDuration;
        clearing += 1;
      }
    });
    rinseSamples += 1;
    rinseBubbleClock += dt;
    if (rinseBubbleClock >= (lowMotion ? 0.16 : 0.05)) {
      const count = lowMotion ? 1 : 2;
      for (let item = 0; item < count; item += 1) {
        activateBubble(contact.position, { splash: true, intensity: strength });
      }
      rinseBubbleClock = 0;
    }
    root.visible = true;
    markMatrices();
    return { ok: true, clearing, foamRemaining: foamCount };
  }

  function fadeRemainingFoam(fadeDuration, splashCount) {
    if (!surfaceReady) return { ok: false, reason: 'surface_unset' };
    if (paused) return { ok: false, reason: 'paused' };
    foamEntries.forEach((entry) => {
      if (!entry.active) return;
      entry.fadeDuration = fadeDuration;
      entry.fadeRemaining = Math.min(
        entry.fadeRemaining > 0 ? entry.fadeRemaining : fadeDuration,
        fadeDuration,
      );
    });
    for (let item = 0; item < splashCount; item += 1) {
      const angle = (item / splashCount) * Math.PI * 2 + random() * 0.24;
      const position = center.clone()
        .addScaledVector(tangentA, Math.cos(angle) * surfaceRadius * 0.42)
        .addScaledVector(tangentB, Math.sin(angle) * surfaceRadius * 0.42)
        .addScaledVector(normal, 0.025);
      activateBubble(position, { splash: true, intensity: 1 });
    }
    activateSparkle(
      center.clone().addScaledVector(normal, 0.04),
      0xc6f7ff,
      lowMotion ? 0.006 : 0.011,
    );
    root.visible = true;
    markMatrices();
    return { ok: true, splashCount, foamRemaining: foamCount };
  }

  function rinse() {
    return fadeRemainingFoam(lowMotion ? 0.12 : 0.48, lowMotion ? 3 : 10);
  }

  function finishRinse() {
    return fadeRemainingFoam(lowMotion ? 0.08 : 0.28, lowMotion ? 1 : 3);
  }

  function activeCount(entries) {
    return entries.reduce((count, entry) => count + (entry.active ? 1 : 0), 0);
  }

  function updateBubbles(dt) {
    bubbleEntries.forEach((entry, index) => {
      if (!entry.active) return;
      entry.age += dt;
      const progress = clamp(entry.age / entry.lifetime, 0, 1);
      entry.position.addScaledVector(entry.velocity, dt);
      entry.velocity.addScaledVector(normal, entry.splash ? -0.34 * dt : -0.025 * dt);
      const pulse = Math.sin(progress * Math.PI);
      const size = entry.size * (0.45 + pulse * 0.75);
      scale.setScalar(Math.max(0.001, size));
      matrix.compose(entry.position, identityQuaternion, scale);
      bubbles.setMatrixAt(index, matrix);
      if (progress >= 1) {
        entry.active = false;
        bubbles.setMatrixAt(index, hiddenMatrix);
        if (!entry.splash && !lowMotion && index % 11 === 0) {
          activateSparkle(entry.position, bubbleColors[index % bubbleColors.length]);
        }
      }
    });
  }

  function updateSparkles(dt) {
    sparkleEntries.forEach((entry, index) => {
      if (!entry.active) return;
      entry.age += dt;
      const progress = clamp(entry.age / entry.lifetime, 0, 1);
      const size = entry.size * (0.55 + Math.sin(progress * Math.PI) * 1.35);
      scale.set(size, size, size);
      matrix.compose(entry.position, quaternion, scale);
      sparkles.setMatrixAt(index, matrix);
      if (progress >= 1) {
        entry.active = false;
        sparkles.setMatrixAt(index, hiddenMatrix);
      }
    });
  }

  function updateFoam(dt) {
    foamEntries.forEach((entry, index) => {
      if (!entry.active) return;
      if (entry.fadeDuration > 0) {
        entry.fadeRemaining = Math.max(0, entry.fadeRemaining - dt);
        if (entry.fadeRemaining === 0) {
          entry.active = false;
          foamCount = Math.max(0, foamCount - 1);
          foam.setMatrixAt(index, hiddenMatrix);
          return;
        }
      }
      setFoamMatrix(index);
    });
  }

  function update(deltaSeconds) {
    if (paused || !root.visible) return false;
    const dt = clamp(Number.isFinite(deltaSeconds) ? deltaSeconds : 0, 0, 0.1);
    if (dt <= 0) return false;
    updateFoam(dt);
    updateBubbles(dt);
    updateSparkles(dt);
    markMatrices();
    root.visible = foamCount > 0 || activeCount(bubbleEntries) > 0 || activeCount(sparkleEntries) > 0;
    return root.visible;
  }

  function breakStroke() {
    const hadStroke = lastScrub != null;
    lastScrub = null;
    return hadStroke;
  }

  function setReducedMotion(value) {
    lowMotion = Boolean(value);
    return lowMotion;
  }

  function setPaused(value) {
    paused = Boolean(value);
    if (paused) breakStroke();
    return paused;
  }

  function reset() {
    hideAllInstances(foam, foamEntries);
    hideAllInstances(bubbles, bubbleEntries);
    hideAllInstances(sparkles, sparkleEntries);
    foamCount = 0;
    foamCursor = 0;
    foamReuses = 0;
    bubbleCursor = 0;
    sparkleCursor = 0;
    scrubCount = 0;
    scrubSamples = 0;
    rinseSamples = 0;
    foamPeak = 0;
    lastScrub = null;
    scrubBubbleClock = 1;
    rinseBubbleClock = 1;
    foamMaterial.opacity = 0.72;
    randomState = 0x37c0ffee;
    root.visible = false;
    return diagnostics();
  }

  function diagnostics() {
    return Object.freeze({
      surfaceReady,
      paused,
      reducedMotion: lowMotion,
      foamCount,
      foamPeak,
      foamReuses,
      foamFill: FOAM_CAPACITY > 0 ? foamCount / FOAM_CAPACITY : 0,
      scrubSamples,
      rinseSamples,
      activeBubbles: activeCount(bubbleEntries),
      activeSparkles: activeCount(sparkleEntries),
      capacities: Object.freeze({ foam: FOAM_CAPACITY, bubbles: BUBBLE_CAPACITY, sparkles: SPARKLE_CAPACITY }),
      rinsing: foamEntries.some((entry) => entry.active && entry.fadeDuration > 0),
      surface: Object.freeze({
        center: Object.freeze([center.x, center.y, center.z]),
        normal: Object.freeze([normal.x, normal.y, normal.z]),
        radius: surfaceRadius,
      }),
    });
  }

  function dispose() {
    reset();
    root.remove(foam, bubbles, sparkles);
    scene.remove(root);
    foamGeometry.dispose();
    bubbleGeometry.dispose();
    sparkleGeometry.dispose();
    foamMaterial.dispose();
    bubbleMaterial.dispose();
    sparkleMaterial.dispose();
  }

  reset();
  return Object.freeze({
    setSurface,
    scrubAt,
    breakStroke,
    rinseAt,
    rinse,
    finishRinse,
    update,
    setReducedMotion,
    setPaused,
    reset,
    dispose,
    diagnostics,
  });
}
