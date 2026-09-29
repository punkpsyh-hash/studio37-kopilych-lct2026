const EPSILON = 1e-6;

function vector3(THREE, value, fallback) {
  if (value?.isVector3) return value.clone();
  const source = Array.isArray(value) ? value : fallback;
  return new THREE.Vector3(source[0], source[1], source[2]);
}

export function isDishSurfaceContact(center, point, radius) {
  const centerX = center?.x ?? center?.[0];
  const centerZ = center?.z ?? center?.[2];
  const pointX = point?.x ?? point?.[0];
  const pointZ = point?.z ?? point?.[2];
  if (![centerX, centerZ, pointX, pointZ, radius].every(Number.isFinite) || radius < 0) return false;
  return Math.hypot(centerX - pointX, centerZ - pointZ) <= radius + EPSILON;
}

/**
 * Runtime-owned dish water VFX. The caller owns stage, audio and timing.
 */
export function createDishWater(THREE, {
  parent = null,
  nozzle = [-0.11, 0.908, -2.08],
  contact = [-0.11, 0.606, -2.08],
  normal = [0, 1, 0],
} = {}) {
  if (!THREE?.Group || !THREE?.CylinderGeometry || !THREE?.RingGeometry) {
    throw new Error('createDishWater needs the pinned THREE namespace');
  }

  const group = new THREE.Group();
  group.name = 'VFX__dish_water_stream';
  group.visible = false;

  const streamMaterial = new THREE.MeshBasicMaterial({
    color: 0x86d9ef, transparent: true, opacity: 0.64, depthWrite: false,
    side: THREE.DoubleSide, toneMapped: false,
  });
  const stream = new THREE.Mesh(new THREE.CylinderGeometry(1, 1.12, 1, 14, 1, true), streamMaterial);
  stream.name = 'VFX__dish_water_stream_body';
  stream.renderOrder = 5;
  group.add(stream);

  const coreMaterial = streamMaterial.clone();
  coreMaterial.color.setHex(0xd9f7ff);
  coreMaterial.opacity = 0.34;
  const core = new THREE.Mesh(new THREE.CylinderGeometry(1, 1.08, 1, 10, 1, true), coreMaterial);
  core.name = 'VFX__dish_water_stream_core';
  core.renderOrder = 6;
  group.add(core);

  const splash = new THREE.Group();
  splash.name = 'VFX__dish_water_splash';
  const splashMaterials = [0.48, 0.3].map((opacity) => new THREE.MeshBasicMaterial({
    color: 0xa8e9f7, transparent: true, opacity, depthWrite: false,
    side: THREE.DoubleSide, toneMapped: false,
  }));
  const rings = splashMaterials.map((material, index) => {
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.035, 0.057, 28), material);
    ring.name = `VFX__dish_water_ripple_${index + 1}`;
    ring.renderOrder = 5;
    splash.add(ring);
    return ring;
  });
  group.add(splash);
  parent?.add(group);

  const up = new THREE.Vector3(0, 1, 0);
  const ringNormal = new THREE.Vector3(0, 0, 1);
  const start = new THREE.Vector3();
  const end = new THREE.Vector3();
  const surfaceNormal = new THREE.Vector3();
  const direction = new THREE.Vector3();
  const midpoint = new THREE.Vector3();
  let length = 0;
  let phase = 0;
  let flowing = false;
  let paused = false;
  let disposed = false;

  function assertAlive() {
    if (disposed) throw new Error('dish water controller is disposed');
  }

  function setEndpoints({ nozzle: nextNozzle = start, contact: nextContact = end,
    normal: nextNormal = surfaceNormal } = {}) {
    assertAlive();
    start.copy(vector3(THREE, nextNozzle, [-0.11, 0.908, -2.08]));
    end.copy(vector3(THREE, nextContact, [-0.11, 0.606, -2.08]));
    surfaceNormal.copy(vector3(THREE, nextNormal, [0, 1, 0])).normalize();
    direction.subVectors(end, start);
    length = direction.length();
    if (!(length > EPSILON)) throw new Error('dish water nozzle and contact must differ');
    direction.multiplyScalar(1 / length);
    midpoint.addVectors(start, end).multiplyScalar(0.5);
    stream.position.copy(midpoint);
    core.position.copy(midpoint);
    stream.quaternion.setFromUnitVectors(up, direction);
    core.quaternion.copy(stream.quaternion);
    stream.scale.set(0.013, length, 0.013);
    core.scale.set(0.0045, length * 0.997, 0.0045);
    splash.position.copy(end).addScaledVector(surfaceNormal, 0.003);
    splash.quaternion.setFromUnitVectors(ringNormal, surfaceNormal);
    return diagnostics();
  }

  function setFlowing(value) {
    assertAlive();
    flowing = Boolean(value);
    group.visible = flowing;
    splash.visible = flowing;
    if (!flowing) phase = 0;
    return diagnostics();
  }

  function setPaused(value) {
    assertAlive();
    paused = Boolean(value);
    return diagnostics();
  }

  function update(deltaSeconds) {
    assertAlive();
    if (!flowing || paused) return diagnostics();
    phase = (phase + Math.max(0, Number(deltaSeconds) || 0) * 1.7) % 1;
    const pulse = 1 + Math.sin(phase * Math.PI * 2) * 0.055;
    stream.scale.x = 0.013 * pulse;
    stream.scale.z = 0.013 * pulse;
    streamMaterial.opacity = 0.6 + Math.sin(phase * Math.PI * 2 + 0.7) * 0.06;
    rings.forEach((ring, index) => {
      const ripple = (phase + index * 0.5) % 1;
      const scale = 0.82 + ripple * 1.35;
      ring.scale.setScalar(scale);
      ring.material.opacity = (index ? 0.3 : 0.48) * (1 - ripple) ** 1.4;
    });
    return diagnostics();
  }

  function reset() {
    assertAlive();
    flowing = false;
    paused = false;
    phase = 0;
    group.visible = false;
    splash.visible = false;
    return diagnostics();
  }

  function diagnostics() {
    return {
      flowing, paused, visible: group.visible, splashVisible: splash.visible,
      nozzle: start.toArray(), contact: end.toArray(), normal: surfaceNormal.toArray(),
      length, phase, disposed,
    };
  }

  function dispose() {
    if (disposed) return;
    group.removeFromParent();
    stream.geometry.dispose();
    core.geometry.dispose();
    rings.forEach((ring) => ring.geometry.dispose());
    streamMaterial.dispose();
    coreMaterial.dispose();
    splashMaterials.forEach((material) => material.dispose());
    disposed = true;
  }

  setEndpoints({ nozzle, contact, normal });
  return Object.freeze({ group, setEndpoints, setFlowing, setPaused, update, reset, diagnostics, dispose });
}
