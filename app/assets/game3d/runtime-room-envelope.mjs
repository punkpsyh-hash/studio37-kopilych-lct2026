export const LIVING_ROOM_ENVELOPE_FILE = './rooms/living-room-envelope.glb';

export async function attachLivingRoomEnvelope({ roomId, roomRoot, loadGLTF, isCurrent, disposeGLTF }) {
  if (roomId !== 'living') return null;
  if (!roomRoot || typeof loadGLTF !== 'function' || typeof isCurrent !== 'function' ||
      typeof disposeGLTF !== 'function') {
    throw new TypeError('attachLivingRoomEnvelope requires root, loader, current check, and disposer');
  }
  const existing = roomRoot.getObjectByName('ROOM_ENVELOPE__living');
  if (existing) return existing;
  const gltf = await loadGLTF(LIVING_ROOM_ENVELOPE_FILE);
  const envelope = gltf.scene;
  try {
    if (!isCurrent()) {
      disposeGLTF(envelope);
      return null;
    }
    envelope.name = 'ROOM_ENVELOPE__living';
    const expected = [
      'ENVELOPE__living__left_front', 'ENVELOPE__living__left_rear',
      'ENVELOPE__living__left_lintel', 'ENVELOPE__living__right_front',
      'ENVELOPE__living__right_rear', 'ENVELOPE__living__right_lintel',
    ];
    const missing = expected.filter((name) => !envelope.getObjectByName(name));
    if (missing.length) throw new Error(`Living envelope missing nodes: ${missing.join(', ')}`);
    roomRoot.add(envelope);
    envelope.updateMatrixWorld(true);
    return envelope;
  } catch (error) {
    disposeGLTF(envelope);
    throw error;
  }
}
