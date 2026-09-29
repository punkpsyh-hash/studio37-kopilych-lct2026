// Candidate-only eyelid material for the existing service mesh. A compatible
// derivative supplies rest-surface mask/donor attributes and a shallow morph.
// Install after coat recoloring, so the donor follows the selected fur palette.
const installed = new WeakSet();

export function installMaterialBlink(root) {
  let count = 0;
  root.traverse((mesh) => {
    const index = mesh.morphTargetDictionary?.EyeBlink;
    const data = mesh.geometry?.getAttribute('_blink_data');
    const donor = mesh.geometry?.getAttribute('_blink_uv');
    if (!mesh.isSkinnedMesh || !Number.isInteger(index) || !data || !donor
      || installed.has(mesh)) return;
    const morph = mesh.geometry.morphAttributes.position?.[index];
    if (data.itemSize !== 3 || donor.itemSize !== 2
      || data.count !== mesh.geometry.attributes.position.count || donor.count !== data.count
      || !morph || morph.itemSize !== 3 || morph.count !== data.count) {
      throw new Error('Material blink requires matching mask/height/horizontal and donor UV attributes');
    }
    const closure = { value: 0 };
    const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    if (materials.some((material) => !material.isMeshStandardMaterial || !material.map)) {
      throw new Error('Material blink requires the original textured standard material');
    }
    for (const material of materials) {
      const previousCompile = material.onBeforeCompile;
      const previousKey = material.customProgramCacheKey();
      material.onBeforeCompile = function (shader, renderer) {
        previousCompile.call(this, shader, renderer);
        shader.uniforms.materialBlinkClosure = closure;
        shader.vertexShader = `
attribute vec3 _blink_data;
attribute vec2 _blink_uv;
varying vec3 vMaterialBlinkData;
varying vec2 vMaterialBlinkUV;
` + shader.vertexShader;
        shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>', `
#include <begin_vertex>
vMaterialBlinkData = _blink_data;
vMaterialBlinkUV = _blink_uv;
`);
        shader.fragmentShader = `
uniform float materialBlinkClosure;
varying vec3 vMaterialBlinkData;
varying vec2 vMaterialBlinkUV;
vec2 materialBlinkEdges() {
  float u = clamp(vMaterialBlinkData.z, -1.0, 1.0);
  float rim = 1.12 * sqrt(max(0.0, 1.0 - u * u));
  float seam = -0.20 + 0.32 * u * u;
  // The upper lid travels farther; both edges meet on the same curved seam.
  return vec2(mix(rim, seam, materialBlinkClosure),
    mix(-rim, seam, materialBlinkClosure * materialBlinkClosure));
}
float materialBlinkCover() {
  // No fractional-opacity eyelid: the covered iris is replaced completely.
  // Fade only at onset, to keep closure=0 pixel-identical to the source.
  vec2 edges = materialBlinkEdges();
  float upper = smoothstep(-0.055, 0.055, vMaterialBlinkData.y - edges.x);
  float lower = 1.0 - smoothstep(-0.055, 0.055, vMaterialBlinkData.y - edges.y);
  return clamp(vMaterialBlinkData.x, 0.0, 1.0)
    * min(1.0, upper + lower)
    * smoothstep(0.0, 0.04, materialBlinkClosure);
}
` + shader.fragmentShader;
        for (const marker of ['#include <map_fragment>', '#include <roughnessmap_fragment>']) {
          if (!shader.fragmentShader.includes(marker)) throw new Error('Missing material blink shader chunk: ' + marker);
        }
        shader.fragmentShader = shader.fragmentShader.replace('#include <map_fragment>', `
#include <map_fragment>
float materialBlinkCoverage = materialBlinkCover();
vec3 materialBlinkFur = texture2D(map, vMaterialBlinkUV).rgb * diffuse;
diffuseColor.rgb = mix(diffuseColor.rgb, materialBlinkFur, materialBlinkCoverage);
float materialBlinkU = vMaterialBlinkData.z;
float materialBlinkCrease = 1.0 - smoothstep(0.025, 0.055,
  abs(vMaterialBlinkData.y - materialBlinkEdges().x));
materialBlinkCrease *= (1.0 - smoothstep(0.65, 0.85, abs(materialBlinkU)))
  * smoothstep(0.02, 0.12, materialBlinkClosure) * materialBlinkCoverage;
diffuseColor.rgb *= 1.0 - 0.78 * materialBlinkCrease;
`);
        // Existing coat protection applies to exposed iris only. The covered
        // part already contains fur, even halfway through a silver/cream blink.
        if (shader.fragmentShader.includes('uniform float coatBlink;')) {
          const irisProtection = '*(1.0-smoothstep(.80,.98,coatBlink))';
          if (!shader.fragmentShader.includes(irisProtection)) throw new Error('Missing coat iris protection hook');
          shader.fragmentShader = shader.fragmentShader.replace(irisProtection,
            irisProtection + '*(1.0-materialBlinkCoverage)');
        }
        shader.fragmentShader = shader.fragmentShader.replace('#include <roughnessmap_fragment>', `
#include <roughnessmap_fragment>
roughnessFactor = mix(roughnessFactor, 0.92, materialBlinkCover());
`);
      };
      material.customProgramCacheKey = () => previousKey + '|material-blink-candidate-v1';
      material.needsUpdate = true;
    }
    const previousRender = mesh.onBeforeRender;
    mesh.onBeforeRender = function (...args) {
      closure.value = Math.max(0, Math.min(1, this.morphTargetInfluences[index] || 0));
      previousRender.apply(this, args);
    };
    installed.add(mesh);
    count += 1;
  });
  return { installed: count, scope: 'material-blink candidate; explicit compatible derivative required' };
}
