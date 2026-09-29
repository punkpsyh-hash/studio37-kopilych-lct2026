// Rest-space fittings of the existing service cap and bow. Models are one-metre
// wide with their base at Y=0; the head bone carries them through every clip.
export const accessoryFits = {
  kitten: {
    head: ['spine006','spine.006'],
    cap: {width:.20,position:[.04,.616,.305]},
    bow: {width:.11,position:[.15,.602,.39]},
  },
  puppy: {
    head: ['spine011','spine.011'],
    cap: {width:.24,position:[0,.798,.235],pitch:-.08},
    bow: {width:.13,position:[.10,.835,.34]},
  },
  hamster: {
    head: ['spine011','spine.011'],
    cap: {width:.38,position:[-.025,1.34,.59]},
    bow: {width:.23,position:[.20,1.28,.72]},
  },
};

export function attachPetAccessory(petRoot, accessory, species, item) {
  const profile=accessoryFits[species];const fit=profile?.[item];
  if(!fit) throw new Error(`No accessory fitting: ${species}/${item}`);
  const head=profile.head.map(name=>petRoot.getObjectByName(name)).find(Boolean);
  if(!head?.isBone) throw new Error(`Pet has no compatible head bone: ${species}`);
  accessory.name=`ACCESSORY__${item}`;
  accessory.position.fromArray(fit.position);accessory.scale.setScalar(fit.width);
  accessory.rotation.set(fit.pitch||0,0,0);
  petRoot.add(accessory);petRoot.updateMatrixWorld(true);
  let socket=null;
  if(item==='cap') {
    socket=createSurfaceSocket(petRoot,fit);
    socket.offset=socketFrame(socket).invert().multiply(accessory.matrix);
    surfaceSockets.set(accessory,socket);
    accessory.matrixAutoUpdate=false;
    updatePetAccessory(accessory);
  } else head.attach(accessory);
  accessory.userData.petAccessory={species,item,head:head.name};
  const attachment=accessory.matrix.clone();
  return {item,head:head.name,width:fit.width,attachment:attachment.toArray(),
    mode:socket?'skinned_surface':'head_bone',
    anchorSamples:socket?socket.anchors.map(group=>group.map(a=>({mesh:a.mesh.name,index:a.index}))):[]};
}

function rootPoint(mesh,index,rootInverse) {
  return mesh.getVertexPosition(index,new Vector3()).applyMatrix4(mesh.matrixWorld).applyMatrix4(rootInverse);
}

function createSurfaceSocket(root,fit) {
  const inverse=root.matrixWorld.clone().invert();const candidates=[];
  const center=new Vector3().fromArray(fit.position);
  root.traverse(mesh=>{
    if(!mesh.isSkinnedMesh)return;
    for(let index=0;index<mesh.geometry.attributes.position.count;index++) {
      const p=rootPoint(mesh,index,inverse);
      if(p.distanceTo(center)<fit.width*.85)candidates.push({mesh,index,rest:p});
    }
  });
  if(candidates.length<24)throw new Error('Insufficient scalp surface for cap attachment');
  const queries=[new Vector3(0,0,.22),new Vector3(0,0,-.22),new Vector3(.28,0,0)]
    .map(p=>p.multiplyScalar(fit.width).add(center));
  const anchors=queries.map(query=>[...candidates].sort((a,b)=>a.rest.distanceToSquared(query)-b.rest.distanceToSquared(query)).slice(0,12));
  return {root,anchors,offset:new Matrix4()};
}

function socketFrame(socket) {
  const inverse=socket.root.matrixWorld.clone().invert();
  const [front,back,right]=socket.anchors.map(group=>{
    const average=new Vector3();for(const a of group)average.add(rootPoint(a.mesh,a.index,inverse));return average.multiplyScalar(1/group.length);
  });
  const center=front.clone().add(back).multiplyScalar(.5);
  const forward=front.clone().sub(back).normalize();
  const up=forward.clone().cross(right.clone().sub(center)).normalize();
  const across=up.clone().cross(forward).normalize();
  if(!Number.isFinite(up.lengthSq())||up.lengthSq()<.9)throw new Error('Degenerate scalp attachment frame');
  return new Matrix4().makeBasis(across,up,forward).setPosition(center);
}

export function updatePetAccessory(accessory) {
  const socket=surfaceSockets.get(accessory);
  if(!socket)return false;
  accessory.matrix.copy(socketFrame(socket).multiply(socket.offset));
  accessory.matrixWorldNeedsUpdate=true;
  return true;
}
import { Matrix4, Vector3 } from './vendor/three.module.min.js';
const surfaceSockets=new WeakMap();
