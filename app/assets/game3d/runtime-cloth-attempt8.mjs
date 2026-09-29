/** Isolated same-mesh GPU deformation. No application wiring or animation loop. */
const attachedMeshes=new WeakSet();
const attachedGeometries=new WeakMap();
const EXPECTED = Object.freeze({
  position:'8b2f740350f8e56c3ae9095a6ddd04373533bf66cbffd3c2f76cbd3142699fd6',
  uv:'a1d6084848a2061b2c17aef309609bf00f02d9eb35d7abe4d8b359761b347fd1',
  index:'9ee8d2667b489a872a6aa8eaba272630e7ce4d1d2d885b29274d38935026d3b3',
  sidecar:'3e61a3cc19bfa4ff3c9a80a2a7b4d00f7bfdf19e6294761bdbb4067f58bac1f1',
  glb:'6d68fd0995001e2fb794df2f83f9cb42423ccf20fdb199d806e3688474c4a54b',
  config:'eb32581279d5484f773b8981bdd614f260509f3df86d55b878163c7ee51991d3',
});
async function digest(bytes) {
  if (!globalThis.crypto?.subtle) throw new Error('SHA-256 verification requires WebCrypto');
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    byte => byte.toString(16).padStart(2,'0')).join('');
}
function attributeBytes(attribute, type, itemSize, count) {
  if (!attribute || attribute.isInterleavedBufferAttribute || attribute.itemSize!==itemSize ||
      attribute.count!==count || !(attribute.array instanceof type)) throw new Error('Unexpected source geometry layout');
  return attribute.array.buffer.slice(attribute.array.byteOffset,
    attribute.array.byteOffset+attribute.array.byteLength);
}
function decodeSidecar(bytes, count) {
  const view=new DataView(bytes);
  if(view.byteLength<12 || String.fromCharCode(...new Uint8Array(bytes,0,4))!=='C8D1' ||
     view.getUint32(4,true)!==count) throw new Error('Attempt8 sidecar header mismatch');
  const records=view.getUint32(8,true);
  if(view.byteLength!==12+16*records) throw new Error('Attempt8 sidecar length mismatch');
  const dense=new Float32Array(count*3);
  let previous=-1;
  for(let i=0;i<records;i++) {
    const offset=12+i*16,index=view.getUint32(offset,true);
    if(index<=previous||index>=count)throw new Error('Attempt8 sidecar indices are unsorted or out of range');
    previous=index;
    for(let axis=0;axis<3;axis++) {
      const value=view.getFloat32(offset+4+axis*4,true);
      if(!Number.isFinite(value))throw new Error('Non-finite Attempt8 correction');
      dense[index*3+axis]=value;
    }
  }
  return {dense,records};
}
/** Verify the exact 416k-r3 arrays before binding the sparse, vertex-indexed field. */
export async function createAttempt8ClothFold({mesh, THREE, config, sidecar, sourceGlbBytes}) {
  if (!mesh?.isMesh || !mesh.geometry || !THREE || !config || !(sidecar instanceof ArrayBuffer) ||
      !(sourceGlbBytes instanceof ArrayBuffer))
    throw new TypeError('Expected mesh, THREE, pinned config, sidecar and source GLB ArrayBuffers');
  if(config.assetSha256!==EXPECTED.glb || await digest(new TextEncoder().encode(JSON.stringify(config)))!==EXPECTED.config)
    throw new Error('Attempt8 config mismatch');
  if(await digest(sourceGlbBytes)!==EXPECTED.glb)throw new Error('Attempt8 GLB SHA-256 mismatch');
  const geometry=mesh.geometry, count=222982;
  if(geometry.getAttribute('clothDelta') && !attachedGeometries.has(geometry))
    throw new Error('Geometry has an unrelated clothDelta attribute');
  const index=geometry.index;
  if(!index || index.count!==1248000)throw new Error('Expected 416,000 triangles');
  const checks=[
    [attributeBytes(geometry.getAttribute('position'),Float32Array,3,count),EXPECTED.position],
    [attributeBytes(geometry.getAttribute('uv'),Float32Array,2,count),EXPECTED.uv],
    [attributeBytes(index,Uint32Array,1,1248000),EXPECTED.index],
    [sidecar,EXPECTED.sidecar],
  ];
  for(const [bytes,expected] of checks)if(await digest(bytes)!==expected)
    throw new Error('Attempt8 source geometry or sidecar SHA-256 mismatch');
  const {dense,records}=decodeSidecar(sidecar,count);
  let shared=attachedGeometries.get(geometry);
  if(!shared) {
    geometry.setAttribute('clothDelta',new THREE.BufferAttribute(dense,3));
    shared={refs:0};
    attachedGeometries.set(geometry,shared);
  }
  try {
    const controller=createAnalyticClothFold({mesh,THREE,config});
    shared.refs++;
    const originalDispose=controller.dispose;
    controller.dispose=()=>{
      if(controller.diagnostics().disposed)return;
      originalDispose();
      if(--shared.refs===0) {
        geometry.deleteAttribute('clothDelta');
        attachedGeometries.delete(geometry);
      }
    };
    return Object.assign(controller,{sparseVertices:records,sidecarBytes:sidecar.byteLength});
  } catch(error) {
    if(shared.refs===0) {
      geometry.deleteAttribute('clothDelta');
      attachedGeometries.delete(geometry);
    }
    throw error;
  }
}
export const CLOTH_GLSL = `
attribute vec3 clothDelta;
uniform float clothCorrection;
uniform float clothPreparation;
uniform vec2 clothProgress;
uniform vec2 clothBendLength;
uniform vec2 clothMidY;
uniform float clothFlattenY;
uniform float clothExtraY;
// Restricted inputs [-pi/2,pi]; avoid driver-dependent low-accuracy native trig.
float clothSin(float angle) {
  float x = angle > 1.5707963267948966 ? 3.141592653589793-angle : angle;
  float xx = x*x;
  return x*(1.0+xx*(-0.16666666666666667+xx*(0.008333333333333333+xx*(-0.0001984126984126984+xx*(0.0000027557319223985893+xx*(-0.00000002505210838544172+xx*0.00000000016059043836821615))))));
}
float clothCos(float angle) { return clothSin(1.5707963267948966-angle); }
void clothBend(inout vec3 p, inout vec3 n, int axis, float progress, float length, float mid, bool unitNormal) {
  float d = axis == 2 ? p.z : p.x;
  if (progress < 1.0e-7 || d <= 0.0) return;
  float theta = 3.141592653589793 * progress;
  float radius = length / theta;
  float phi = clamp(d / length, 0.0, 1.0) * theta;
  float offset = p.y - mid;
  float tail = max(d - length, 0.0);
  float s = clothSin(phi), c = clothCos(phi);
  float q = (radius - offset) * s + tail * clothCos(theta);
  float halfSine = clothSin(phi * 0.5);
  p.y = mid + 2.0 * radius * halfSine * halfSine + offset * c + tail * clothSin(theta);
  float stretch = d < length ? 1.0 - offset / radius : 1.0;
  float nq = (axis == 2 ? n.z : n.x) / stretch;
  float ny = n.y;
  if (axis == 2) { p.z = q; n.z = nq*c - ny*s; }
  else { p.x = q; n.x = nq*c - ny*s; }
  n.y = nq*s + ny*c;
  if (unitNormal) n = normalize(n);
}
void clothApply(inout vec3 p, inout vec3 n) {
  if (clothPreparation <= 0.0) return;
  vec3 source = p;
  float scale = mix(1.0, clothFlattenY, clothPreparation);
  p.y *= scale; n.y /= scale; n = normalize(n);
  clothBend(p,n,2,clothProgress.x,clothBendLength.x,clothMidY.x,true);
  if (clothExtraY > 0.0 && clothProgress.y > 0.0 && source.x > 0.0) {
    float gateT = clamp(source.x/0.03,0.0,1.0);
    float gate = gateT*gateT*(3.0-2.0*gateT);
    float gateDerivative = source.x < 0.03 ? 6.0*gateT*(1.0-gateT)/0.03 : 0.0;
    vec2 offset = vec2(source.x-0.135,source.z+0.036);
    vec2 variance = vec2(0.055*0.055,0.025*0.025);
    float radial = exp(-0.5*dot(offset/variance,offset));
    float field = gate*radial;
    float dx = radial*(gateDerivative-gate*offset.x/variance.x);
    float dz = -field*offset.y/variance.y;
    float activation = clothProgress.y*clothProgress.y*(3.0-2.0*clothProgress.y);
    float extra = clothExtraY*activation;
    vec3 gradient = extra*vec3(source.y*dx,field,source.y*dz);
    gradient.y /= scale;
    vec3 firstGradientPosition = source; firstGradientPosition.y *= scale;
    clothBend(firstGradientPosition,gradient,2,clothProgress.x,clothBendLength.x,clothMidY.x,false);
    n = normalize(n-gradient*(n.y/(1.0+gradient.y)));
    p.y += source.y*extra*field;
  }
  clothBend(p,n,0,clothProgress.y,clothBendLength.y,clothMidY.y,true);
  p += clothCorrection * clothDelta;
}
`;

function createAnalyticClothFold({mesh, THREE, config}) {
  if (!mesh?.isMesh || Array.isArray(mesh.material) || mesh.geometry.morphAttributes.position?.length) throw new Error('Expected one static service mesh');
  if (attachedMeshes.has(mesh)) throw new Error('Cloth controller already attached to mesh');
  if (!mesh.geometry.attributes.position || !mesh.geometry.attributes.normal || !mesh.geometry.attributes.uv) throw new Error('Expected source position, normal and UV');
  if (!Number.isFinite(config.flattenY) || !(config.flattenY > 0) || config.bendLengths.length !== 2 || config.bendLengths.some(v=>!Number.isFinite(v)||v<=0) || config.midY.length !== 2 || config.midY.some(v=>!Number.isFinite(v))) throw new Error('Invalid cloth parameters');
  const extraY=config.extraY??0;
  if (!Number.isFinite(extraY)||extraY<0||extraY>.08) throw new Error('Unsupported thickness correction');
  const envelope=config.midYEnvelope;
  if(extraY>0&&!envelope)throw new Error('Thickness correction requires its verified midpoint envelope');
  if(envelope&&(extraY!==.08||config.flattenY!==.08||config.bendLengths[0]!==.08||config.bendLengths[1]!==.16||config.midY[0]!==0))throw new Error('Midpoint envelope is verified only for E008/L016');
  let lowerLines,upperLines;
  if(envelope){
    for(const lines of [envelope.lowerLines,envelope.upperLines])if(!Array.isArray(lines)||!lines.length||lines.some(line=>!Array.isArray(line)||line.length!==2||line.some(v=>!Number.isFinite(v))))throw new Error('Invalid midpoint envelope');
    lowerLines=envelope.lowerLines.map(line=>[...line]);upperLines=envelope.upperLines.map(line=>[...line]);
    const initialMiddle=(Math.min(...lowerLines.map(line=>line[0]))+Math.max(...upperLines.map(line=>line[0])))/2;
    if(Math.abs(config.midY[1]-initialMiddle)>1e-12)throw new Error('Initial midpoint differs from asset envelope');
  }
  const uniforms = {
    clothPreparation:{value:0}, clothProgress:{value:new THREE.Vector2()},
    clothBendLength:{value:new THREE.Vector2(...config.bendLengths)},
    clothMidY:{value:new THREE.Vector2(...config.midY)}, clothFlattenY:{value:config.flattenY},clothExtraY:{value:extraY},
    clothCorrection:{value:0},
  };
  const original = {material:mesh.material,depth:mesh.customDepthMaterial,distance:mesh.customDistanceMaterial,culled:mesh.frustumCulled,geometry:mesh.geometry};
  const material = mesh.material.clone();
  const depth = new THREE.MeshDepthMaterial({depthPacking:THREE.RGBADepthPacking});
  const distance = new THREE.MeshDistanceMaterial();
  const compile = shader => {
    Object.assign(shader.uniforms,uniforms);
    shader.vertexShader = shader.vertexShader.replace('#include <common>','#include <common>\n'+CLOTH_GLSL)
      .replace('#include <beginnormal_vertex>','#include <beginnormal_vertex>\nvec3 clothNormalPosition = position; clothApply(clothNormalPosition, objectNormal);')
      .replace('#include <begin_vertex>','vec3 transformed = position; vec3 clothDummyNormal = normal; clothApply(transformed, clothDummyNormal);');
  };
  for (const item of [material,depth,distance]) { item.onBeforeCompile=compile; item.customProgramCacheKey=()=> 'cloth-attempt8-v1'; }
  mesh.material=material;mesh.customDepthMaterial=depth;mesh.customDistanceMaterial=distance;
  attachedMeshes.add(mesh);
  // Bounds of the source alone cannot cull the raised moving flap correctly.
  mesh.frustumCulled=false;
  let disposed=false;
  const check=()=>{if(disposed)throw new Error('Cloth controller disposed');};
  const unit=value=>{if(!Number.isFinite(value))throw new TypeError('Progress must be finite');return Math.max(0,Math.min(1,value));};
  const updateMid=progress=>{if(!envelope)return;const activation=progress*progress*(3-2*progress);const lo=Math.min(...lowerLines.map(([c,s])=>c+s*activation)),hi=Math.max(...upperLines.map(([c,s])=>c+s*activation));uniforms.clothMidY.value.y=(lo+hi)/2;};
  const setProgresses=values=>{check();const a=unit(values[0]),b=unit(values[1]);if(b>0&&a<1)throw new RangeError('Second fold requires completed first fold');uniforms.clothPreparation.value=1;uniforms.clothProgress.value.set(a,b);uniforms.clothCorrection.value=b*b*(3-2*b);updateMid(b);};
  return {
    mesh, geometry:mesh.geometry, uniforms,
    prepare(value){check();const p=unit(value);uniforms.clothProgress.value.set(0,0);uniforms.clothPreparation.value=p;uniforms.clothCorrection.value=0;updateMid(0);},
    setProgresses,
    setPose(step,value){check();if(step!==0&&step!==1)throw new RangeError('Fold step must be 0 or 1');setProgresses(step===0?[value,0]:[1,value]);},
    reset(){check();uniforms.clothPreparation.value=0;uniforms.clothProgress.value.set(0,0);uniforms.clothCorrection.value=0;updateMid(0);},
    diagnostics(){return {prepared:uniforms.clothPreparation.value,progresses:uniforms.clothProgress.value.toArray(),morphTargets:0,geometryShared:mesh.geometry===original.geometry,estimatedPlyThickness:null,disposed};},
    dispose(){if(disposed)return;mesh.material=original.material;mesh.customDepthMaterial=original.depth;mesh.customDistanceMaterial=original.distance;mesh.frustumCulled=original.culled;for(const item of [material,depth,distance])item.dispose();attachedMeshes.delete(mesh);disposed=true;},
  };
}
