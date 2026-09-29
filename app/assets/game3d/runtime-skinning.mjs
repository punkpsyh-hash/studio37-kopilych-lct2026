import {
  Float32BufferAttribute,
  Matrix4,
  MeshDepthMaterial,
  MeshDistanceMaterial,
  RGBADepthPacking,
  ShaderChunk,
  Vector3,
} from './vendor/three.module.min.js';

const PROGRAM_KEY = 'extended-skinning-8-v1';
const installedMeshes = new WeakSet();
const installedShadowMeshes = new WeakSet();
const basePosition = new Vector3();
const weightedPosition = new Vector3();
const boneMatrix = new Matrix4();

const component = (attribute, index, lane) => {
  if (lane === 0) return attribute.getX(index);
  if (lane === 1) return attribute.getY(index);
  if (lane === 2) return attribute.getZ(index);
  return attribute.getW(index);
};

function replaceChunk(source, name, replacement) {
  const marker = `#include <${name}>`;
  if (!source.includes(marker) || typeof ShaderChunk[name] !== 'string') {
    throw new Error(`Extended skinning requires Three ShaderChunk.${name}`);
  }
  return source.replace(marker, replacement);
}

function extendVertexShader(source, needsNormals = true) {
  let shader = source.replace(
    '#include <skinning_pars_vertex>',
    `#include <skinning_pars_vertex>\n#ifdef USE_SKINNING\nattribute vec4 skinIndex1;\nattribute vec4 skinWeight1;\n#endif`,
  );

  shader = replaceChunk(shader, 'skinbase_vertex', `#include <skinbase_vertex>
#ifdef USE_SKINNING
  mat4 boneMatX1 = getBoneMatrix( skinIndex1.x );
  mat4 boneMatY1 = getBoneMatrix( skinIndex1.y );
  mat4 boneMatZ1 = getBoneMatrix( skinIndex1.z );
  mat4 boneMatW1 = getBoneMatrix( skinIndex1.w );
#endif`);

  if (needsNormals || shader.includes('#include <skinnormal_vertex>')) {
    shader = replaceChunk(shader, 'skinnormal_vertex', `#ifdef USE_SKINNING
  mat4 skinMatrix = mat4( 0.0 );
  skinMatrix += skinWeight.x * boneMatX;
  skinMatrix += skinWeight.y * boneMatY;
  skinMatrix += skinWeight.z * boneMatZ;
  skinMatrix += skinWeight.w * boneMatW;
  skinMatrix += skinWeight1.x * boneMatX1;
  skinMatrix += skinWeight1.y * boneMatY1;
  skinMatrix += skinWeight1.z * boneMatZ1;
  skinMatrix += skinWeight1.w * boneMatW1;
  skinMatrix = bindMatrixInverse * skinMatrix * bindMatrix;
  objectNormal = vec4( skinMatrix * vec4( objectNormal, 0.0 ) ).xyz;
  #ifdef USE_TANGENT
    objectTangent = vec4( skinMatrix * vec4( objectTangent, 0.0 ) ).xyz;
  #endif
#endif`);
  }

  return replaceChunk(shader, 'skinning_vertex', `#ifdef USE_SKINNING
  vec4 skinVertex = bindMatrix * vec4( transformed, 1.0 );
  vec4 skinned = vec4( 0.0 );
  skinned += boneMatX * skinVertex * skinWeight.x;
  skinned += boneMatY * skinVertex * skinWeight.y;
  skinned += boneMatZ * skinVertex * skinWeight.z;
  skinned += boneMatW * skinVertex * skinWeight.w;
  skinned += boneMatX1 * skinVertex * skinWeight1.x;
  skinned += boneMatY1 * skinVertex * skinWeight1.y;
  skinned += boneMatZ1 * skinVertex * skinWeight1.z;
  skinned += boneMatW1 * skinVertex * skinWeight1.w;
  transformed = ( bindMatrixInverse * skinned ).xyz;
#endif`);
}

function extendMaterial(material, needsNormals = true) {
  const extended = material.clone();
  const previousCompile = material.onBeforeCompile;
  const previousKey = material.customProgramCacheKey();
  extended.onBeforeCompile = function onBeforeCompile(shader, renderer) {
    previousCompile.call(this, shader, renderer);
    shader.vertexShader = extendVertexShader(shader.vertexShader, needsNormals);
  };
  extended.customProgramCacheKey = () => `${previousKey}|${PROGRAM_KEY}`;
  return extended;
}

/** Match the visible eight-weight surface in directional and point shadows. */
export function installExtendedShadowSkinning(mesh) {
  if (!installedMeshes.has(mesh) || installedShadowMeshes.has(mesh)) return false;
  mesh.customDepthMaterial = extendMaterial(new MeshDepthMaterial({ depthPacking: RGBADepthPacking }), false);
  mesh.customDistanceMaterial = extendMaterial(new MeshDistanceMaterial(), false);
  installedShadowMeshes.add(mesh);
  return true;
}

function normalizeEightWeights(geometry) {
  const first = geometry.getAttribute('skinWeight');
  const second = geometry.getAttribute('skinWeight1');
  if (!first || !second || first.count !== second.count) {
    throw new Error('Extended skinning requires matching skinWeight and skinWeight1 attributes');
  }

  const firstValues = new Float32Array(first.count * 4);
  const secondValues = new Float32Array(second.count * 4);
  for (let index = 0; index < first.count; index += 1) {
    let firstSum = 0;
    let secondSum = 0;
    for (let lane = 0; lane < 4; lane += 1) {
      firstSum += component(first, index, lane);
      secondSum += component(second, index, lane);
    }
    const sum = firstSum + secondSum;
    if (!(sum > 0) || !Number.isFinite(sum)) {
      firstValues[index * 4] = 1;
      continue;
    }
    // Blender's export_all_influences GLB normalizes WEIGHTS_0 to one while
    // leaving WEIGHTS_1 as its absolute share. Reconstruct the missing share
    // before applying the general glTF combined-set normalization fallback.
    const splitSet = secondSum > 0 && secondSum < 1 && Math.abs(firstSum - 1) <= 1e-5;
    const firstScale = splitSet ? (1 - secondSum) / firstSum : 1 / sum;
    const secondScale = splitSet ? 1 : 1 / sum;
    for (let lane = 0; lane < 4; lane += 1) {
      firstValues[index * 4 + lane] = component(first, index, lane) * firstScale;
      secondValues[index * 4 + lane] = component(second, index, lane) * secondScale;
    }
  }
  geometry.setAttribute('skinWeight', new Float32BufferAttribute(firstValues, 4));
  geometry.setAttribute('skinWeight1', new Float32BufferAttribute(secondValues, 4));
}

function applyEightBoneTransform(index, target) {
  const geometry = this.geometry;
  const indices = [geometry.getAttribute('skinIndex'), geometry.getAttribute('skinIndex1')];
  const weights = [geometry.getAttribute('skinWeight'), geometry.getAttribute('skinWeight1')];
  basePosition.copy(target).applyMatrix4(this.bindMatrix);
  target.set(0, 0, 0);

  for (let set = 0; set < 2; set += 1) {
    for (let lane = 0; lane < 4; lane += 1) {
      const weight = component(weights[set], index, lane);
      if (weight === 0) continue;
      const boneIndex = component(indices[set], index, lane);
      const bone = this.skeleton.bones[boneIndex];
      const inverse = this.skeleton.boneInverses[boneIndex];
      if (!bone || !inverse) throw new Error(`Invalid skin joint ${boneIndex} at vertex ${index}`);
      boneMatrix.multiplyMatrices(bone.matrixWorld, inverse);
      target.addScaledVector(weightedPosition.copy(basePosition).applyMatrix4(boneMatrix), weight);
    }
  }
  return target.applyMatrix4(this.bindMatrixInverse);
}

/** Installs eight-influence CPU and GPU skinning on one hydrated SkinnedMesh. */
export function installExtendedSkinning(mesh) {
  if (!mesh?.isSkinnedMesh) return false;
  if (installedMeshes.has(mesh)) return true;
  const geometry = mesh.geometry;
  const skinIndex = geometry?.getAttribute('skinIndex');
  const skinWeight = geometry?.getAttribute('skinWeight');
  const skinIndex1 = geometry?.getAttribute('skinIndex1');
  const skinWeight1 = geometry?.getAttribute('skinWeight1');
  if (!skinIndex1 && !skinWeight1) return false;
  const positionCount = geometry.getAttribute('position')?.count;
  if (!skinIndex || !skinWeight || !skinIndex1 || !skinWeight1
      || [skinIndex.count, skinWeight.count, skinIndex1.count, skinWeight1.count]
        .some((count) => count !== positionCount)) {
    throw new Error(`Incomplete extended skin attributes on ${mesh.name || '<unnamed>'}`);
  }

  normalizeEightWeights(geometry);
  mesh.material = Array.isArray(mesh.material)
    ? mesh.material.map(material => extendMaterial(material))
    : extendMaterial(mesh.material);
  mesh.applyBoneTransform = applyEightBoneTransform;
  mesh.userData.extendedSkinning = { influences: 8, programKey: PROGRAM_KEY };
  installedMeshes.add(mesh);
  return true;
}

function cloneAccessor(attribute) {
  return attribute.clone();
}

/** Restores glTF JOINTS_1/WEIGHTS_1 accessors omitted by Three r160 GLTFLoader. */
export async function installExtendedSkinningFromGLTF(gltf) {
  const parser = gltf?.parser;
  if (!parser?.json || !parser.associations || typeof parser.getDependency !== 'function') {
    throw new Error('Extended skinning requires a GLTFLoader result with parser associations');
  }

  const meshes = [];
  gltf.scene?.traverse((object) => {
    if (object.isSkinnedMesh) meshes.push(object);
  });

  let installed = 0;
  for (const mesh of meshes) {
    if (installedMeshes.has(mesh)) continue;
    const association = parser.associations.get(mesh);
    const primitive = parser.json.meshes?.[association?.meshes]?.primitives?.[association?.primitives];
    const attributes = primitive?.attributes;
    const hasIndices1 = attributes?.JOINTS_1 !== undefined;
    const hasWeights1 = attributes?.WEIGHTS_1 !== undefined;
    if (!hasIndices1 && !hasWeights1) continue;
    if (!hasIndices1 || !hasWeights1) {
      throw new Error(`glTF primitive for ${mesh.name || '<unnamed>'} has incomplete JOINTS_1/WEIGHTS_1`);
    }

    const required = ['JOINTS_0', 'WEIGHTS_0', 'JOINTS_1', 'WEIGHTS_1'];
    if (required.some((semantic) => attributes[semantic] === undefined)) {
      throw new Error(`glTF primitive for ${mesh.name || '<unnamed>'} lacks complete skin accessors`);
    }
    const [indices0, weights0, indices1, weights1] = await Promise.all(
      required.map((semantic) => parser.getDependency('accessor', attributes[semantic])),
    );
    if (new Set([indices0.count, weights0.count, indices1.count, weights1.count]).size !== 1) {
      throw new Error(`glTF skin accessor counts differ on ${mesh.name || '<unnamed>'}`);
    }

    // GLTFLoader normalized WEIGHTS_0 alone while creating the SkinnedMesh.
    // Replace it with the raw accessor, then normalize all eight weights once.
    mesh.geometry = mesh.geometry.clone();
    mesh.geometry.setAttribute('skinIndex', cloneAccessor(indices0));
    mesh.geometry.setAttribute('skinWeight', cloneAccessor(weights0));
    mesh.geometry.setAttribute('skinIndex1', cloneAccessor(indices1));
    mesh.geometry.setAttribute('skinWeight1', cloneAccessor(weights1));
    if (installExtendedSkinning(mesh)) installed += 1;
  }

  return { installed, skinnedMeshes: meshes.length };
}

export const extendedSkinningProgramKey = PROGRAM_KEY;
