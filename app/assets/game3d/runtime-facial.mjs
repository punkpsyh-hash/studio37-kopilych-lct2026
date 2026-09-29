import * as THREE from './vendor/three.module.min.js';

// A restrained crease on the closed lid. The service mesh and its
// actual morphs provide closure; this material detail preserves its expression
// when the original fur UVs stretch across a large cartoon eye.
const installed = new WeakSet();
const lidProfiles = {
  kitten: {eyes:[[-.029,.484,.036,.036],[.107,.507,.051,.042]],tilt:.17,depth:[.27,.34]},
  puppy: {eyes:[[-.077,.713,.041,.033],[.075,.713,.041,.033]],tilt:0,depth:[.30,.36]},
  hamster: {eyes:[[-.265,.989,.096,.090],[.186,1.012,.122,.091]],tilt:.05,depth:[.40,.55]},
};

export function installFacialLidCrease(root, species, clips = []) {
  const profile = lidProfiles[species];
  if (!profile) return { installed: 0 };
  const headNames = species === 'kitten' ? ['spine006','spine.006'] : ['spine011','spine.011'];
  const head = headNames.map(name=>root.getObjectByName(name)).find(Boolean);
  const idle = clips.find(clip=>clip.name === species+'_idle');
  if (!head || !idle) return {installed:0,reason:'production_reference_unavailable'};
  // Capture the original production-neutral head frame before runtime scale
  // and placement. Raw bind positions may have been re-bound to new weights.
  const referenceMixer = new THREE.AnimationMixer(root);
  referenceMixer.clipAction(idle).play();referenceMixer.setTime(0);
  root.updateMatrixWorld(true);
  const referenceHead = head.matrixWorld.clone();
  referenceMixer.stopAllAction();referenceMixer.uncacheRoot(root);
  root.updateMatrixWorld(true);
  const num = value => value.toFixed(6);
  const cosine = num(Math.cos(profile.tilt)), sine = num(Math.sin(profile.tilt));
  const eyeInk = profile.eyes.map(([x,y,rx,ry])=>
    `closedLidLine(vec2(${num(x)},${num(y)}),vec2(${num(rx)},${num(ry)}))`).join(',');
  let count = 0;
  root.traverse((mesh) => {
    const index = mesh.morphTargetDictionary?.EyeBlink;
    if (!mesh.isSkinnedMesh || index === undefined || installed.has(mesh)) return;
    const uniform = { value: mesh.morphTargetInfluences[index] || 0 };
    const referenceFromWorld = {value:new THREE.Matrix4()};
    const patch = (original) => {
      // Facial authoring marks the existing lid polygons. A projected crease
      // must not also paint nearby whiskers or cheek tufts in the same volume.
      if (!original.name.includes('deforming_eyelid')) return original;
      const material = original.clone();
      const previousCompile = original.onBeforeCompile;
      const previousKey = original.customProgramCacheKey();
      material.onBeforeCompile = function(shader, renderer) {
        previousCompile.call(this, shader, renderer);
        shader.uniforms.lidClosure = uniform;
        shader.uniforms.lidReferenceFromWorld = referenceFromWorld;
        shader.vertexShader = 'varying vec3 vLidPosition;\nuniform mat4 lidReferenceFromWorld;\n' + shader.vertexShader;
        // The extended 8-weight skinning hook replaces skinning_vertex itself.
        // project_vertex remains after either standard or extended skinning.
        const marker = '#include <project_vertex>';
        if (!shader.vertexShader.includes(marker)) throw new Error('Missing facial projection shader chunk');
        shader.vertexShader = shader.vertexShader.replace(marker,
          marker + '\nvLidPosition = (lidReferenceFromWorld * modelMatrix * vec4(transformed,1.0)).xyz;');
        shader.fragmentShader = `
uniform float lidClosure;
varying vec3 vLidPosition;
float closedLidLine(vec2 center, vec2 radius) {
  vec2 offset = vLidPosition.xy-center;
  vec2 q = vec2(dot(offset,vec2(${cosine},${sine})),
                dot(offset,vec2(-${sine},${cosine})))/radius;
  float distanceToLine = abs(q.y + 0.10 + 0.12*q.x*q.x);
  float ink = 1.0-smoothstep(0.035,0.065,distanceToLine);
  return ink*(1.0-smoothstep(0.72,0.96,abs(q.x)));
}
` + shader.fragmentShader;
        const colorMarker = '#include <color_fragment>';
        if (!shader.fragmentShader.includes(colorMarker)) throw new Error('Missing facial color shader chunk');
        shader.fragmentShader = shader.fragmentShader.replace(colorMarker, colorMarker + `
float lidInk = max(${eyeInk});
lidInk *= smoothstep(0.72,0.98,lidClosure)*smoothstep(${num(profile.depth[0])},${num(profile.depth[1])},vLidPosition.z);
diffuseColor.rgb = mix(diffuseColor.rgb,vec3(0.035,0.012,0.004),lidInk*0.84);
`);
      };
      material.customProgramCacheKey = () => previousKey + '|'+species+'-lid-crease-headspace-v3';
      return material;
    };
    mesh.material = Array.isArray(mesh.material) ? mesh.material.map(patch) : patch(mesh.material);
    const previousRender = mesh.onBeforeRender;
    mesh.onBeforeRender = function(...args) {
      uniform.value = this.morphTargetInfluences[index] || 0;
      referenceFromWorld.value.copy(head.matrixWorld).invert().premultiply(referenceHead);
      previousRender.apply(this, args);
    };
    installed.add(mesh);
    count += 1;
  });
  return { installed: count, referenceSpace:'production-neutral head' };
}
