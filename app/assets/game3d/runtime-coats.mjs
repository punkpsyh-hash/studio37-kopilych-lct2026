// Authored palette variants of the same service texture. The warm-fur mask
// preserves white markings, pink skin, dark features and the original iris.
const palettes = {
  kitten: ['рыжий', 'серебристый полосатый', 'кремовый'],
  puppy: ['медовый', 'чёрно-белый', 'шоколадный'],
  hamster: ['золотистый', 'кремовый', 'серо-белый'],
};
const eyes = {
  kitten: [[-.029,.484,.033,.036],[.107,.507,.046,.042],.17,.27],
  puppy: [[-.077,.713,.041,.033],[.075,.713,.041,.033],0,.30],
  hamster: [[-.265,.989,.086,.090],[.186,1.012,.110,.091],.05,.40],
};
const variants = {
  kitten: ['vec3(1.0)', 'vec3(.58,.61,.64)*(.18+.82*shade)', 'vec3(.98,.77,.46)*(.42+.58*sqrt(shade))'],
  puppy: ['vec3(1.0)', 'vec3(max(.006,shade*.105))', 'vec3(.32,.115,.043)*(.16+.84*sqrt(shade))'],
  hamster: ['vec3(1.0)', 'vec3(.98,.80,.50)*(.44+.56*sqrt(shade))', 'vec3(.54,.57,.60)*(.18+.82*shade)'],
};

export function installPetCoat(root, species, color) {
  const index = Number(String(color).replace('fur_', ''))-1;
  if (!palettes[species] || !Number.isInteger(index) || index < 0 || index > 2) {
    return { installed: 0, reason: 'unknown_palette' };
  }
  if (index === 0) return { installed: 0, name: palettes[species][index], original: true };
  const [left, right, tilt, front] = eyes[species];
  const pinkProtection=species==='hamster' ? `
float pinkMask=max(protectPink(vec2(-.381,1.230),vec2(.135,.157),.335),
                   protectPink(vec2(.405,1.257),vec2(.130,.156),.475));
pinkMask=max(pinkMask,protectPink(vec2(-.084,.884),vec2(.071,.049),.920));
pinkMask*=1.0-smoothstep(.34,.46,warmHue);
fur*=1.0-pinkMask;
` : '';
  const vec = (v) => `vec4(${v.map(n => n.toFixed(6)).join(',')})`;
  let count=0;
  root.traverse(mesh => {
    if (!mesh.isMesh || !mesh.material) return;
    const blinkIndex=mesh.morphTargetDictionary?.EyeBlink;
    const blink={value:Number.isInteger(blinkIndex)?mesh.morphTargetInfluences[blinkIndex]:0};
    const previousRender=mesh.onBeforeRender;
    mesh.onBeforeRender=function(...args){
      blink.value=Number.isInteger(blinkIndex)?this.morphTargetInfluences[blinkIndex]:0;
      previousRender.apply(this,args);
    };
    for (const material of (Array.isArray(mesh.material) ? mesh.material : [mesh.material])) {
      if (material.userData.petCoat) continue;
      const previousCompile = material.onBeforeCompile;
      const previousKey = material.customProgramCacheKey();
      material.onBeforeCompile = function(shader, renderer) {
        previousCompile.call(this, shader, renderer);
        shader.uniforms.coatBlink=blink;
        shader.vertexShader='varying vec3 vCoatRest;\n'+shader.vertexShader;
        shader.vertexShader=shader.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\nvCoatRest=position;');
        shader.fragmentShader=`
varying vec3 vCoatRest;
uniform float coatBlink;
float protectPink(vec2 center,vec2 radii,float frontDepth) {
  return (1.0-smoothstep(.90,1.06,length((vCoatRest.xy-center)/radii)))*smoothstep(frontDepth,frontDepth+.020,vCoatRest.z);
}
float protectIris(vec4 eye) {
  vec2 d=vCoatRest.xy-eye.xy;
  float a=${tilt.toFixed(6)};
  vec2 q=vec2(dot(d,vec2(cos(a),sin(a))),dot(d,vec2(-sin(a),cos(a))))/eye.zw;
  return (1.0-smoothstep(.78,.96,length(q)))*smoothstep(${front.toFixed(6)},${(front+.03).toFixed(6)},vCoatRest.z);
}
`+shader.fragmentShader;
        shader.fragmentShader=shader.fragmentShader.replace('#include <map_fragment>', `#include <map_fragment>
vec3 coatColor=pow(max(diffuseColor.rgb,vec3(0.0)),vec3(1.0/2.2));
float warmSaturation=(coatColor.r-coatColor.b)/max(.001,coatColor.r);
float warmHue=(coatColor.g-coatColor.b)/max(.001,coatColor.r-coatColor.b);
float fur=smoothstep(.32,.52,warmSaturation)*smoothstep(.10,.22,warmHue);
// The iris protection belongs to an exposed eye. At full closure the same
// folded surface is the lid, and must not leave original-colour fur specks.
fur*=1.0-max(protectIris(${vec(left)}),protectIris(${vec(right)}))*(1.0-smoothstep(.80,.98,coatBlink));
${pinkProtection}
float shade=clamp(dot(diffuseColor.rgb,vec3(.2126,.7152,.0722)),0.0,1.0);
diffuseColor.rgb=mix(diffuseColor.rgb,${variants[species][index]},fur);
`);
      };
      material.customProgramCacheKey=()=>previousKey+`|coat-v2:${species}:${index}`;
      material.userData.petCoat={ species, index, name:palettes[species][index] };
      material.needsUpdate=true;
      count+=1;
    }
  });
  return { installed:count, name:palettes[species][index], original:false };
}

export const petCoatNames=palettes;
