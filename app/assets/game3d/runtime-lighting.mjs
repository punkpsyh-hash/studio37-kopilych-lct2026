import * as THREE from './vendor/three.module.min.js';
import {installExtendedShadowSkinning} from './runtime-skinning.mjs';

// Fixture positions come from the existing fixtures-v2 Blender pass, converted
// to room-local glTF axes. Blender watts are not copied into Three candela.
const profiles = {
  living: {node:'PROP__living__floor_lamp',position:[-2.585,.96,-1.69],color:0xffdbb3,intensity:.5,glowMin:1.08,glowMax:2.1,bounce:[0,1.15,2.42],bounceIntensity:2,indirect:1.45},
  kitchen:{node:'PROP__kitchen__pendant_lamp',position:[.17,2.185,.80],color:0xffebcc,intensity:10,glowMin:2.18,glowMax:2.32,bounce:[0,1.1,2.40],bounceIntensity:1.3,indirect:.9},
  bathroom:{node:'FIXTURE__bathroom__pendant',position:[0,2.585,-.10],color:0xffefd6,intensity:9,glowMin:2.61,glowMax:2.74,bounce:[0,1.0,2.38],bounceIntensity:1.1,indirect:.85},
};

// Floor coverings lie flat on the floor: they receive shadows, but their own
// shadow is invisible. The braided rug alone is 360k triangles, and a point
// light redraws every caster into six cube faces.
const FLAT_FLOOR_COVERING=/(^|_)(rug|carpet|threshold)(_|$)/i;
function isFlatFloorCovering(mesh){
  for(let node=mesh;node;node=node.parent)if(FLAT_FLOOR_COVERING.test(node.name||''))return true;
  return false;
}

export function prepareRoomShadows(root) {
  root?.traverse(mesh=>{
    if(!mesh.isMesh)return;
    mesh.castShadow=false;mesh.receiveShadow=false;
    if(mesh.isSkinnedMesh)installExtendedShadowSkinning(mesh);
  });
}

function fixtureEmission(node, minY, maxY, color) {
  const enabled={value:0},rgb=new THREE.Color(color);
  node?.traverse(mesh=>{
    if(!mesh.isMesh)return;
    mesh.material=(Array.isArray(mesh.material)?mesh.material:[mesh.material]).map(original=>{
      const material=original.clone(),previous=original.onBeforeCompile,key=original.customProgramCacheKey();
      material.emissive.setRGB(0,0,0);material.emissiveIntensity=0;
      material.onBeforeCompile=function(shader,renderer){
        previous.call(this,shader,renderer);shader.uniforms.fixtureOn=enabled;
        shader.vertexShader='varying float vFixtureHeight;\n'+shader.vertexShader;
        shader.vertexShader=shader.vertexShader.replace('#include <project_vertex>','#include <project_vertex>\nvFixtureHeight=(modelMatrix*vec4(transformed,1.0)).y;');
        shader.fragmentShader='varying float vFixtureHeight;\nuniform float fixtureOn;\n'+shader.fragmentShader;
        shader.fragmentShader=shader.fragmentShader.replace('#include <emissivemap_fragment>',`#include <emissivemap_fragment>
float glowMask=smoothstep(${(minY-.025).toFixed(6)},${minY.toFixed(6)},vFixtureHeight)*(1.0-smoothstep(${maxY.toFixed(6)},${(maxY+.025).toFixed(6)},vFixtureHeight));
totalEmissiveRadiance+=vec3(${rgb.r.toFixed(6)},${rgb.g.toFixed(6)},${rgb.b.toFixed(6)})*glowMask*fixtureOn*.42;`);
      };
      material.customProgramCacheKey=()=>key+`|fixture-emission:${minY}:${maxY}:${color}`;
      return material;
    });
    if(mesh.material.length===1)mesh.material=mesh.material[0];
  });
  return enabled;
}

/** No independent ambient/key light. The modest wall bounce follows its lamp. */
export async function createRoomLighting({roomRoot,roomId,renderer,loadGLTF,nodeTransforms=[]}) {
  const profile=profiles[roomId];if(!profile)throw Error('Unknown room lighting '+roomId);
  if(roomId==='bathroom'&&!roomRoot.getObjectByName(profile.node)){
    const gltf=await loadGLTF('props/bathroom-pendant.glb');
    gltf.scene.position.set(0,2.88,-.10);roomRoot.add(gltf.scene);
  }
  roomRoot.updateMatrixWorld(true);
  roomRoot.traverse(mesh=>{if(mesh.isMesh)for(const material of(Array.isArray(mesh.material)?mesh.material:[mesh.material])){
    material.emissive?.setRGB(0,0,0);if('emissiveIntensity'in material)material.emissiveIntensity=0;
  }});
  const fixture=roomRoot.getObjectByName(profile.node);if(!fixture)throw Error('Missing visible fixture '+profile.node);
  const fixtureOffset=new THREE.Vector3();
  for(const transform of nodeTransforms)if(transform.node===profile.node&&Array.isArray(transform.offset))fixtureOffset.add(new THREE.Vector3(...transform.offset));
  const group=new THREE.Group();group.name='RUNTIME__fixture_lighting';roomRoot.add(group);
  const main=new THREE.PointLight(profile.color,profile.intensity,12,2);main.name='LIGHT__'+roomId+'__main';main.position.fromArray(profile.position);main.castShadow=true;
  main.position.add(fixtureOffset);
  main.shadow.mapSize.set(512,512);main.shadow.camera.near=.03;main.shadow.camera.far=12;main.shadow.bias=-.00015;main.shadow.normalBias=.008;main.shadow.radius=2;group.add(main);
  // Approximate diffuse reflection from the front wall; the source is the lamp,
  // and both its energy and glow go exactly to zero when that lamp is off.
  const bounce=new THREE.PointLight(profile.color,profile.bounceIntensity,8,2);bounce.name='BOUNCE__'+roomId+'__main';bounce.position.fromArray(profile.bounce);group.add(bounce);
  // A low-order approximation of the same lamp's diffuse room reflection.
  // It has no independent switch or energy when all visible fixtures are off.
  const indirect=new THREE.HemisphereLight(profile.color,0x927660,profile.indirect);indirect.name='INDIRECT__'+roomId+'__fixtures';group.add(indirect);
  const glow=fixtureEmission(fixture,profile.glowMin+fixtureOffset.y,profile.glowMax+fixtureOffset.y,profile.color);
  const optional=[];
  if(roomId==='living'){
    const stars=roomRoot.getObjectByName('PROP__living__goal_stars');
    if(stars){const light=new THREE.PointLight(0xffd299,.65,3.8,2);light.position.set(.58,.79,-2.005);light.name='LIGHT__living__stars';group.add(light);optional.push({id:'stars',node:stars,light,intensity:.65,indirect:.25,glow:fixtureEmission(stars,.63,1.2,0xffd299)});}
  }
  prepareRoomShadows(roomRoot);
  // The light source is inside this shade; its self-shadow projected sharp
  // silhouettes onto the adjacent wall. Other furniture still casts shadows.
  if(roomId==='living')fixture.traverse(mesh=>{if(mesh.isMesh)mesh.castShadow=false;});
  renderer.shadowMap.enabled=false;
  let last={lampOn:true,owned:[],purchased:[]};
  const update=state=>{
    last={...last,...state};const on=last.lampOn!==false;
    main.intensity=on?profile.intensity:0;bounce.intensity=on?profile.bounceIntensity:0;glow.value=on?1:0;
    indirect.intensity=on?profile.indirect:0;
    const owned=new Set([...(last.owned||[]),...(last.purchased||[])]);
    for(const item of optional){const active=owned.has(item.id)&&last[item.id+'On']!==false;item.light.intensity=active?item.intensity:0;item.glow.value=active?1:0;if(active)indirect.intensity+=item.indirect;}
  };
  const registerOptionalFixture=({id,node,position,color=0xffd299,intensity=2,glowMin,glowMax})=>{
    if(!['nightlight'].includes(id)||!node||optional.some(item=>item.id===id))return false;
    const bounds=new THREE.Box3().setFromObject(node);if(bounds.isEmpty())return false;
    const light=new THREE.PointLight(color,intensity,3.8,2);light.name='LIGHT__'+roomId+'__'+id;
    light.position.copy(position?new THREE.Vector3(...position):bounds.getCenter(new THREE.Vector3()));group.add(light);
    optional.push({id,node,light,intensity,indirect:.3,glow:fixtureEmission(node,glowMin??bounds.min.y,glowMax??bounds.max.y,color)});
    update(last);return true;
  };
  const diagnostics=()=>({room:roomId,independentAmbient:0,fixture:profile.node,main:{position:main.position.toArray(),intensity:main.intensity,shadow:main.castShadow},bounce:{position:bounce.position.toArray(),intensity:bounce.intensity,derivedFrom:main.name},indirect:{intensity:indirect.intensity,derivedFrom:'enabled visible fixtures',approximation:'diffuse hemisphere'},optional:optional.map(item=>({id:item.id,intensity:item.light.intensity})),shadowMapSize:main.shadow.mapSize.toArray()});
  update(last);
  return {update,diagnostics,registerOptionalFixture,dispose(){main.shadow.map?.dispose();main.shadow.mapPass?.dispose();group.removeFromParent();}};
}
