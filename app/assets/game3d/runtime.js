import * as THREE from './vendor/three.module.min.js';
import { GLTFLoader } from './vendor/loaders/GLTFLoader.js';
import { API_VERSION, JOB_DEFINITIONS, ProtocolError, createProtocol, createDishRound, createJobRound } from './runtime-protocol.mjs';
import { createRuntimeAudio } from './runtime-audio.mjs';
import { installExtendedSkinningFromGLTF } from './runtime-skinning.mjs';
import { installFacialLidCrease } from './runtime-facial.mjs';
import { installPetCoat } from './runtime-coats.mjs';
import { attachPetAccessory, updatePetAccessory } from './runtime-accessories.mjs';
import { createRoomLighting, prepareRoomShadows } from './runtime-lighting.mjs';
import { createPetGrowthController } from './runtime-growth.mjs';
import { createDishFoam } from './runtime-dish-foam.mjs';
import { createDishWater, isDishSurfaceContact } from './runtime-dish-water.mjs';
import {
  DISH_PLATE_CENTER_XZ, DISH_SPONGE_PARK_POSITION, DISH_SPONGE_TRAVEL_Y,
  dishSpongeContactPose, dishSpongePointerPose,
} from './runtime-dish-sponge-contact.mjs';
import { createCoverageField, pushDustPile } from './runtime-minigame-state.mjs';
import { createCleaningMask } from './runtime-cleaning-mask.mjs';
import { createAttempt8ClothFold } from './runtime-cloth-attempt8.mjs';
import { attachLivingRoomEnvelope } from './runtime-room-envelope.mjs';
import { createRuntimeQualityController, applyRendererQuality, applyTextureFiltering, applyTextureResolution, textureResolutionDiagnostics } from './runtime-quality.mjs';

const canvas = document.getElementById('scene');
const status = document.getElementById('status');
const statusText = document.getElementById('status-text');
const dishUi = document.getElementById('dish-ui');
const dishEyebrow = document.getElementById('dish-eyebrow');
const dishInstruction = document.getElementById('dish-instruction');
const dishProgress = document.getElementById('dish-progress');
const dishStepButton = document.getElementById('dish-step');
const dishCancelButton = document.getElementById('dish-cancel');
const protocol = createProtocol();
const runtimeAudio = createRuntimeAudio();
let qualityController = createRuntimeQualityController();
let dishRound = createDishRound();
let dishJobPeriod = 0;
let dishPointer = null;
const dishCleanedPatches = new Set();
let jobRound = null;
let jobPeriod = 0;
let jobCompletedSteps = [];
let jobPointer = null;
let jobTapSelection = null;
let jobFeedback = null;
const jobCompletedTaskIds = new Set();
const jobCompletedTaskOrder = [];
const jobOccupiedTargetIds = new Set();
let jobPlacementBusy = false;
let jobPlacementSerial = 0;
let activeJobPlacement = null;
const jobCoverageFields = new Map();
const jobDustPiles = new Map();
const jobDirtVisuals = new Map();
const jobClothMaterialState = [];
const jobClothFolds = new Map();
let activeJobClothFold = null;
let jobPanFillVisual = null;
let jobPanFillLevel = 0;
let jobPanEmptying = false;
let jobPanEmptyProgress = 0;
let j06BroomParkPending = false;
let accessibleMinigameToken = 0;
let dishAccessibleStepPending = null;

function genericJobActive() {
  return jobRound && !['idle', 'complete', 'rejected'].includes(jobRound.getState().stage);
}

function anyMinigameActive() {
  return dishRound.getState().stage !== 'idle' || genericJobActive();
}
const loader = new GLTFLoader();
const descriptorUrl = new URL('./rooms/descriptor.json', location.href);
const petPreview = new URLSearchParams(location.search).get('petPreview');
const MODEL_FILES = Object.freeze({ kitten: 'kitten', puppy: 'puppy', hamster: 'hamster' });
const DEFAULT_PET_SET = 'integrated-v1';
const PREFERRED_ROOM = Object.freeze({
  feed: 'kitchen', play: 'living', clean: 'bathroom', stars: 'living', nightlight: 'living', wash_dishes: 'kitchen',
  job_j01: 'kitchen', job_j02: 'living', job_j03: 'bathroom', job_j04: 'kitchen', job_j05: 'living', job_j06: 'living',
});
const GUIDANCE_ACTIONS = new Set(['feed', 'play', 'clean', 'wash_dishes', 'job_j01', 'job_j02', 'job_j03', 'job_j04', 'job_j05', 'job_j06']);
const ACTIONS = new Set(['feed', 'play', 'clean', 'stars', 'nightlight', 'room', 'wash_dishes', 'job_j01', 'job_j02', 'job_j03', 'job_j04', 'job_j05', 'job_j06']);
const BRIDGE_QUEUE_LIMIT = 48;
const TARGET_FRAME_MS = 1000 / 30;
const JOB_TASKS = Object.freeze({
  J02: Object.freeze([
    { kind: 'sort', source: 'single_book', target: [2.42, 0.582, -2.25], targetId: 'living_shelf_low', surface: 'vertical', hint: 'Поставь книгу на свободную полку' },
    { kind: 'sort', source: 'teddy_toy', target: [0.43, 0.35, -2.14], targetId: 'toy_chest', surface: 'floor', hint: 'Посади мишку на сундук' },
    { kind: 'sort', source: 'single_book_2', target: [2.58, 1.409, -2.25], targetId: 'living_shelf_high', surface: 'vertical', hint: 'Поставь книгу на свободную полку' },
  ]),
  J03: Object.freeze([
    { kind: 'fold', source: 'unfolded_towel_1', targetId: 'fold_towel_1', mode: 'fold_drag', hint: 'Проведи от одного края полотенца к другому' },
    { kind: 'fold', source: 'unfolded_towel_2', targetId: 'fold_towel_2', mode: 'fold_drag', hint: 'Сложи второе полотенце от края до края' },
    { kind: 'shelf', source: 'unfolded_towel_1', targetProp: 'towel_shelf', targetId: 'towel_shelf', surface: 'vertical', hint: 'Положи полотенце на полку' },
    { kind: 'shelf', source: 'unfolded_towel_2', targetProp: 'towel_shelf', targetId: 'towel_shelf', surface: 'vertical', hint: 'Положи второе полотенце на полку' },
  ]),
  J04: Object.freeze(['circle', 'square', 'star', 'triangle'].map((shape) => Object.freeze({
    kind: 'sort', source: `package_${shape}`, targetProp: `bin_${shape}`,
    targetId: `bin_${shape}`, surface: 'floor', hint: 'Совмести одинаковые значки',
  }))),
  J05: Object.freeze([
    { kind: 'wipe', source: 'wiping_cloth', target: [2.18, 0.582, -2.25], targetId: 'shelf_dirt_1', surface: 'floor', tool: true, hint: 'Проведи салфеткой по пыли' },
    { kind: 'wipe', source: 'wiping_cloth', target: [2.47, 0.582, -2.25], targetId: 'shelf_dirt_2', surface: 'floor', tool: true, hint: 'Протри следующий участок полки' },
    { kind: 'wipe', source: 'wiping_cloth', target: [2.76, 0.582, -2.25], targetId: 'shelf_dirt_3', surface: 'floor', tool: true, hint: 'Протри последний участок полки' },
    { kind: 'put_away', source: 'wiping_cloth', target: [2.48, 0.16225462238575591, -2.25], targetId: 'cloth_home', surface: 'floor', hint: 'Верни салфетку на место' },
  ]),
  J06: Object.freeze([
    { kind: 'sweep', source: 'short_broom', target: [1.86, 0.014, -0.5], targetId: 'dust_1', surface: 'floor', tool: true, hint: 'Смети пыль к совку' },
    { kind: 'sweep', source: 'short_broom', target: [1.98, 0.014, -0.08], targetId: 'dust_2', surface: 'floor', tool: true, hint: 'Смети вторую кучку' },
    { kind: 'sweep', source: 'short_broom', target: [2.12, 0.014, -0.62], targetId: 'dust_3', surface: 'floor', tool: true, hint: 'Смети последнюю кучку' },
    { kind: 'empty', source: 'dustpan', targetProp: 'waste_bin', targetId: 'waste_bin', surface: 'floor', hint: 'Высыпь пыль из совка' },
    { kind: 'put_away', source: 'short_broom', target: [1.8, 0.024080758165716594, -2.28], targetId: 'broom_home', surface: 'floor', hint: 'Убери веник' },
    { kind: 'put_away', source: 'dustpan', target: [1.48, 0, -2.28], targetId: 'dustpan_home', surface: 'floor', hint: 'Убери совок' },
  ]),
});
const JOB_PLACEMENT_LABELS = Object.freeze({
  single_book: 'Книга у стола',
  single_book_2: 'Книга у кресла',
  teddy_toy: 'Мишка',
  living_shelf_low: 'Нижняя полка',
  living_shelf_high: 'Верхняя полка',
  toy_chest: 'Сундук',
  package_circle: 'Упаковка с кругом',
  package_square: 'Упаковка с квадратом',
  package_star: 'Упаковка со звездой',
  package_triangle: 'Упаковка с треугольником',
  bin_circle: 'Контейнер с кругом',
  bin_square: 'Контейнер с квадратом',
  bin_star: 'Контейнер со звездой',
  bin_triangle: 'Контейнер с треугольником',
});
const J02_BOOK_SOURCES = new Set(['single_book', 'single_book_2']);
const J02_SHELF_TARGETS = new Set(['living_shelf_low', 'living_shelf_high']);
const SORTING_BIN_INTERIOR_Y = 0.0843;

let descriptor = null;
let renderer = null;
let glContext = null;
let webglVersion = 0;
let running = false;
let paused = false;
let visibilityPaused = document.hidden;
let contextLost = false;
let readySent = false;
let frameHandle = 0;
let lastFrameAt = 0;
let roomLoadToken = 0;
let kitchenFridgeLoadSerial = 0;
let kitchenFridgePending = null;
let petLoadToken = 0;
let currentRoomId = null;
let currentPetKey = null;
let loadingPetKey = null;
let roomRoot = null;
let petModel = null;
let petMixer = null;
let petGrowth = null;
let petAccessory = null;
let petClips = new Map();
let activeContact = null;
let contactSerial = 0;
let lastContactDiagnostics = null;
let lastLocomotionDiagnostics = null;
let activeReaction = null;
let lastReactionSerial = null;
let dialogueBottomFraction = 0;
let dialogueFaceNdcY = null;
let previewFramingFocus = null;
let previewBottomFraction = 0;
let previewTargetNdcY = null;
let jobPropLoadToken = 0;
let jobPropsJobId = null;
const jobProps = new Map();
const jobPropAnimationTokens = new WeakMap();
const J03_FOLD_COMPLETE_THRESHOLD = 0.92;
const J06_FLOOR_Y = 0;
const J06_PAN_INTAKE = Object.freeze([2.225, 0.014, -0.3]);
const J06_BROOM_PARK = Object.freeze([1.78, 0, -0.66]);
const J06_WORK_BOUNDS = Object.freeze({ minX: 1.76, maxX: 2.28, minZ: -0.7, maxZ: 0.02 });
let adoptionRoot = null;
let adoptionAssetKey = null;
let petHome = new THREE.Vector3();
let activeTween = null;
let petIdleAction = null;
let roomReadyPromise = Promise.resolve();
let petReadyPromise = Promise.resolve();
let adoptionReadyPromise = Promise.resolve();
let roomLighting = null;
let warnedStageKey = '';
let bridgeRetryCount = 0;
let adoptionVisualToken = 0;
let warnedOpenOnlyBox = false;
let navigationSerial = 0;
let navigation = null;
let roomCurtainTween = null;
let roomCurtainActionId = null;
let cameraTween = null;
const bridgeQueue = [];
const interactionMeshes = [];
const materialClones = new Set();
// Authored in-place gait: stride (master metres, x model scale) and the stance
// duty of the species walk profile. Legacy libraries use a 1 s walk with duty
// 0.62; species-tempo libraries export a different walk length and their duty.
const WALK_GAIT = Object.freeze({
  kitten: { stride: 0.11, duty: 0.65 },
  puppy: { stride: 0.132, duty: 0.6 },
  hamster: { stride: 0.22, duty: 0.72 },
});
const LEGACY_WALK_DUTY = 0.62;
const MAX_LOCOMOTION_TIME_SCALE = 1.5;
const DOOR_APPROACH_METERS = 0.42;

function walkMasterSpeed(species, walkClip) {
  const gait = WALK_GAIT[species];
  if (!gait) return 0;
  const seconds = walkClip?.duration || 1;
  const duty = Math.abs(seconds - 1) < 1e-3 ? LEGACY_WALK_DUTY : gait.duty;
  return gait.stride / (duty * seconds);
}

const scene = new THREE.Scene();
scene.background = new THREE.Color(0xf7eadc);
const camera = new THREE.PerspectiveCamera(38, 1, 0.05, 80);
camera.position.set(0, 2.4, 5.5);
camera.lookAt(0, 1, 0);
const roomCurtain = new THREE.Mesh(
  new THREE.PlaneGeometry(1, 1),
  new THREE.MeshBasicMaterial({ color: 0xf7eadc, transparent: true, opacity: 0,
    depthTest: false, depthWrite: false, toneMapped: false }),
);
roomCurtain.position.z = -0.1;
roomCurtain.renderOrder = 10000;
roomCurtain.visible = false;
camera.add(roomCurtain);

const roomLayer = new THREE.Group();
roomLayer.name = 'RUNTIME__room';
const petLayer = new THREE.Group();
petLayer.name = 'RUNTIME__pet';
const interactionLayer = new THREE.Group();
interactionLayer.name = 'RUNTIME__hit_targets';
const jobPropLayer = new THREE.Group();
jobPropLayer.name = 'RUNTIME__job_props';
const jobGuideLayer = new THREE.Group();
jobGuideLayer.name = 'RUNTIME__job_guidance';
const jobEffectLayer = new THREE.Group();
jobEffectLayer.name = 'RUNTIME__job_effects';
const adoptionLayer = new THREE.Group();
adoptionLayer.name = 'RUNTIME__adoption';
const dishLayer = new THREE.Group();
dishLayer.name = 'RUNTIME__dishes_closeup';
dishLayer.visible = false;
const guidanceLayer = new THREE.Group();
guidanceLayer.name = 'RUNTIME__guidance';
scene.add(roomLayer, jobPropLayer, jobGuideLayer, jobEffectLayer, dishLayer, adoptionLayer, petLayer, interactionLayer, guidanceLayer, camera);
const dishFoam = createDishFoam({ THREE, scene, reducedMotion: false });
const dishDirt = [];
const dishCoverageFields = [];
const DISH_SPOT_THRESHOLD = 0.68;
const DISH_SURFACE_RADIUS = 0.14;
const DISH_SPOT_RADIUS = 0.027;
const DISH_BRUSH_RADIUS = 0.01;
const DISH_RINSE_THRESHOLD = 0.86;
// The upgraded service sink has an upward-facing basin floor at y=.563-.565.
// The service plate's local minY is zero, so this root rests directly on it.
const DISH_PLATE_BASE_Y = 0.571;
const DISH_SURFACE_Y = DISH_PLATE_BASE_Y + 0.035;
const DISH_DIRT_Y = DISH_PLATE_BASE_Y + 0.042;
// Pointer projection stays on the established logical plane. Rendered sponge Y comes from the calibrated support table.
const DISH_SPONGE_CONTACT_Y = DISH_SURFACE_Y - 0.005;
const DISH_WATER_NOZZLE = Object.freeze([-0.11, 0.908, -2.08]);
const DISH_BASIN_CONTACT_Y = 0.568;
const DISH_PLATE_CANONICAL = Object.freeze([-0.1, DISH_PLATE_BASE_Y, -2.08]);
// The plate is held above the narrow basin while rinsing. The exact served
// plate was CPU-checked on a 10 mm grid throughout this bounded plane.
const DISH_RINSE_PLATE_Y = 0.73;
const DISH_RINSE_SURFACE_Y = DISH_RINSE_PLATE_Y + 0.035;
const DISH_RINSE_HALF_EXTENT = 0.06;
const DISH_RINSE_INTENSITY = 1.5;
let dishPlate = null;
let dishSponge = null;
let dishSpongeLogicalContact = null;
let dishSpongeMotionEpoch = 0;
let dishSpongeMotionPhase = 'parked';
let dishSpongeParkingActive = false;
let dishSpongeParked = true;
let dishSpongeParking = Promise.resolve(true);
let dishWater = null;
let dishTap = null;
let dishTapGuide = null;
let dishRinseProgress = 0;
let dishRinsedFoam = 0;
let dishRinseRecoverySerial = 0;
let dishCoverageEmitAt = 0;
let dishResultVisibleUntil = 0;
let dishResultPlacement = Promise.resolve(false);
let dishRinseReady = Promise.resolve(false);
let dishRinsePlateReady = false;
let dishCanonicalization = Promise.resolve(false);
let dishFinishRequest = null;
let jobProgressEmitAt = 0;

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
const clock = new THREE.Clock(false);

function setStatus(message, kind = 'loading') {
  status.hidden = false;
  status.dataset.kind = kind;
  statusText.textContent = message;
}

function hideStatus() {
  status.hidden = true;
  status.removeAttribute('data-kind');
}

function bridgeAvailable() {
  return Boolean(window.KopilychBridge && typeof window.KopilychBridge.postMessage === 'function');
}

function flushBridge() {
  if (!bridgeAvailable()) {
    if (bridgeRetryCount++ < 50) setTimeout(flushBridge, 100);
    return;
  }
  bridgeRetryCount = 0;
  while (bridgeQueue.length) {
    window.KopilychBridge.postMessage(bridgeQueue.shift());
  }
}

function postBridge(message) {
  let payload;
  try {
    payload = JSON.stringify(message);
  } catch (error) {
    console.error('KopilychScene bridge serialization failed', error);
    return;
  }
  if (bridgeAvailable()) {
    window.KopilychBridge.postMessage(payload);
    return;
  }
  if (bridgeQueue.length >= BRIDGE_QUEUE_LIMIT) bridgeQueue.shift();
  bridgeQueue.push(payload);
  flushBridge();
}

function diagnostic(code, details = {}) {
  postBridge({ type: 'diagnostic', code, ...details });
}

function reportError(code, error, recoverable = true, details = {}) {
  const message = error instanceof Error ? error.message : String(error);
  postBridge({ type: 'error', code, message, recoverable, ...details });
  console.error(`[KopilychScene:${code}]`, error);
}

function sameOriginUrl(relative, base = location.href) {
  const url = new URL(relative, base);
  if (url.origin !== location.origin) throw new Error('Cross-origin runtime assets are not allowed');
  return url;
}

function vec3(value, fallback = [0, 0, 0]) {
  if (Array.isArray(value) && value.length >= 3 && value.every(Number.isFinite)) {
    return new THREE.Vector3(value[0], value[1], value[2]);
  }
  if (value && typeof value === 'object' && [value.x, value.y, value.z].every(Number.isFinite)) {
    return new THREE.Vector3(value.x, value.y, value.z);
  }
  return new THREE.Vector3(...fallback);
}

function roomMap(raw) {
  if (Array.isArray(raw)) return Object.fromEntries(raw.map((entry) => [entry.id, entry]));
  if (raw && typeof raw === 'object') return raw;
  throw new Error('descriptor.rooms must be an object or array');
}

function validateDescriptor(raw) {
  if (!raw || typeof raw !== 'object' || raw.schemaVersion !== 1) {
    throw new Error('Unsupported room descriptor schema');
  }
  const rooms = roomMap(raw.rooms);
  for (const id of ['living', 'kitchen', 'bathroom']) {
    const room = rooms[id];
    if (!room || room.id !== id || typeof room.file !== 'string') {
      throw new Error(`Room descriptor is missing ${id}`);
    }
    if (!/^[a-z0-9_.-]+$/i.test(room.file)) throw new Error(`Unsafe room file for ${id}`);
    if (!room.camera || !room.camera.position || !room.camera.target) {
      throw new Error(`Room ${id} is missing camera data`);
    }
  }
  for (const id of Object.keys(HOME_CAMERAS)) Object.assign(rooms[id].camera, HOME_CAMERAS[id]);
  return { ...raw, rooms };
}

// 29.09: вид спереди и чуть сверху — видна вся комната, питомец не «в упор».
const HOME_CAMERAS = {
  living: { position: [0.0, 1.95, 3.75], target: [0.0, 0.35, -0.6], fovDegrees: 58 },
  kitchen: { position: [0.0, 1.95, 3.7], target: [0.0, 0.35, -0.6], fovDegrees: 58 },
  bathroom: { position: [0.2, 1.95, 3.7], target: [0.2, 0.35, -0.6], fovDegrees: 58 },
};

async function loadDescriptor() {
  const response = await fetch(descriptorUrl, { cache: 'no-store', credentials: 'same-origin' });
  if (!response.ok) throw new Error(`Room descriptor HTTP ${response.status}`);
  return validateDescriptor(await response.json());
}

function createRenderer() {
  const attributes = {
    alpha: false,
    antialias: true,
    depth: true,
    stencil: false,
    preserveDrawingBuffer: false,
    powerPreference: 'high-performance',
  };
  glContext = canvas.getContext('webgl2', attributes);
  webglVersion = glContext ? 2 : 0;
  if (!glContext) {
    glContext = canvas.getContext('webgl', attributes) || canvas.getContext('experimental-webgl', attributes);
    webglVersion = glContext ? 1 : 0;
  }
  if (!glContext) throw new Error('WebGL is unavailable');
  let maxTextureSize = 0;
  try { maxTextureSize = Number(glContext.getParameter(glContext.MAX_TEXTURE_SIZE)) || 0; } catch { /* Unknown device hint. */ }
  qualityController = createRuntimeQualityController({
    mode: qualityController.getState().mode,
    hints: {
      deviceMemory: navigator.deviceMemory,
      hardwareConcurrency: navigator.hardwareConcurrency,
      maxTextureSize,
      webglVersion,
    },
  });
  renderer = new THREE.WebGLRenderer({ canvas, context: glContext, antialias: true, alpha: false });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.55;
  renderer.shadowMap.enabled = false;
  resize();
}

let renderedCssWidth = 0;
let renderedCssHeight = 0;
function resize() {
  if (!renderer) return;
  cancelActiveJobClothFold(false);
  if (jobPointer?.kind !== 'fold') restoreJobGesture(jobPointer);
  if (dishPointer) restoreDishGesture(dishPointer);
  jobPointer = null;
  dishPointer = null;
  const state = protocol.getState();
  const width = Math.max(1, canvas.clientWidth || innerWidth);
  const height = Math.max(1, canvas.clientHeight || innerHeight);
  renderedCssWidth = width;
  renderedCssHeight = height;
  applyRendererQuality(renderer, qualityController.getState().profile, {
    devicePixelRatio: window.devicePixelRatio, width, height,
  });
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  if (descriptor && roomRoot && currentRoomId) {
    configureCurrentCamera();
    positionJobPetObserver(false);
  }
  if (roomCurtain.visible) setRoomCurtainOpacity(roomCurtain.material.opacity);
  positionDishCloseup();
}

function positionDishCloseup() {
  // Dish targets live in room coordinates on the authored plate. Keeping the
  // layer in world space makes rotation and safe-area changes preserve contact.
  dishLayer.position.set(0, 0, 0);
  dishLayer.scale.setScalar(1);
}

function rendererDiagnostics() {
  const info = renderer?.info;
  const contextAttributes = glContext?.getContextAttributes?.();
  return {
    webglVersion,
    threeRevision: THREE.REVISION,
    triangles: info?.render?.triangles ?? 0,
    drawCalls: info?.render?.calls ?? 0,
    geometries: info?.memory?.geometries ?? 0,
    textures: info?.memory?.textures ?? 0,
    dpr: renderer?.getPixelRatio?.() ?? 1,
    qualityMode: qualityController.getState().mode,
    qualityTier: qualityController.getState().tier,
    antialiasRequested: true,
    antialias: contextAttributes?.antialias === true,
    maxSamples: webglVersion === 2 ? glContext?.getParameter?.(glContext.MAX_SAMPLES) ?? 0 : 0,
  };
}

function scheduleFrame() {
  if (frameHandle || isRuntimePaused() || contextLost || !renderer) return;
  frameHandle = requestAnimationFrame(renderFrame);
}

function setRoomCurtainOpacity(opacity) {
  const height = 0.2 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  roomCurtain.scale.set(height * camera.aspect * 1.02, height * 1.02, 1);
  roomCurtain.material.opacity = THREE.MathUtils.clamp(opacity, 0, 1);
  roomCurtain.visible = roomCurtain.material.opacity > 0;
}

function updateRoomCurtain(deltaSeconds) {
  if (!roomCurtainTween) {
    if (roomCurtain.visible) setRoomCurtainOpacity(roomCurtain.material.opacity);
    return;
  }
  const tween = roomCurtainTween;
  tween.elapsedMs += deltaSeconds * 1000;
  const t = Math.min(1, tween.elapsedMs / tween.durationMs);
  setRoomCurtainOpacity(THREE.MathUtils.lerp(tween.from, tween.to, t));
  if (t === 1) {
    roomCurtainTween = null;
    tween.resolve(true);
  }
}

function fadeRoomCurtain(to, durationMs = 180) {
  roomCurtainTween?.resolve(false);
  roomCurtainTween = null;
  return new Promise((resolve) => {
    roomCurtainTween = { from: roomCurtain.material.opacity, to, durationMs,
      elapsedMs: 0, resolve };
    scheduleFrame();
  });
}

function clearRoomCurtain() {
  const wasVisible = roomCurtain.visible || roomCurtainTween !== null;
  roomCurtainTween?.resolve(false);
  roomCurtainTween = null;
  roomCurtainActionId = null;
  setRoomCurtainOpacity(0);
  if (wasVisible && renderer && !contextLost) renderer.render(scene, camera);
}

function updateCameraTween(now) {
  if (!cameraTween) return;
  const tween = cameraTween;
  if (tween.lastAt !== null) tween.elapsedMs += Math.max(0, now - tween.lastAt);
  tween.lastAt = now;
  const t = Math.min(1, tween.elapsedMs / tween.durationMs);
  const eased = t * t * (3 - 2 * t);
  camera.position.lerpVectors(tween.fromPosition, tween.toPosition, eased);
  camera.quaternion.slerpQuaternions(tween.fromRotation, tween.toRotation, eased);
  camera.fov = THREE.MathUtils.lerp(tween.fromFov, tween.toFov, eased);
  camera.updateProjectionMatrix();
  if (t === 1) {
    cameraTween = null;
    tween.resolve(true);
  }
}

function moveCameraTo(spec, durationMs = 360) {
  cameraTween?.resolve(false);
  cameraTween = null;
  const target = new THREE.PerspectiveCamera(camera.fov, camera.aspect, camera.near, camera.far);
  target.position.copy(vec3(spec.position));
  target.fov = Number.isFinite(spec.fovDegrees) ? spec.fovDegrees : camera.fov;
  target.lookAt(vec3(spec.target));
  if (protocol.getState().reducedMotion) {
    camera.position.copy(target.position);
    camera.quaternion.copy(target.quaternion);
    camera.fov = target.fov;
    camera.updateProjectionMatrix();
    return Promise.resolve(true);
  }
  return new Promise((resolve) => {
    cameraTween = {
      fromPosition: camera.position.clone(), toPosition: target.position.clone(),
      fromRotation: camera.quaternion.clone(), toRotation: target.quaternion.clone(),
      fromFov: camera.fov, toFov: target.fov, elapsedMs: 0, lastAt: null, durationMs, resolve,
    };
    scheduleFrame();
  });
}

function cancelCameraTween() {
  cameraTween?.resolve(false);
  cameraTween = null;
}

// Idle lives between actions: the reconciler starts it whenever nothing else
// drives the pet and stops it before locomotion, contacts, reactions and
// minigames, so one-shot clips never blend with the breathing loop.
function reconcilePetIdle() {
  const state = protocol.getState();
  const wantIdle = !!petMixer && !!petModel && !state.reducedMotion
    && !(state.mode === 'adoption' && !state.adoptionOpen)
    && !activeTween && !activeContact && !activeReaction
    && !anyMinigameActive() && !isRuntimePaused() && !contextLost;
  if (wantIdle && !petIdleAction) {
    const clip = petClips.get(`${state.species}_idle`);
    if (!clip) return;
    // Dedicated action identity: contact cues reuse the cached action of the
    // original clip, so the loop must own a clone to avoid stopping a cue.
    const loopClip = clip.clone();
    loopClip.name = `${clip.name}__loop`;
    petIdleAction = petMixer.clipAction(loopClip);
    petIdleAction.reset();
    petIdleAction.setLoop(THREE.LoopRepeat, Infinity);
    petIdleAction.play();
  } else if (!wantIdle && petIdleAction) {
    petIdleAction.stop();
    petIdleAction = null;
  }
}

// The closed adoption box hops gently to invite a tap: a short jump every
// couple of seconds plus a soft wobble. Reversible transform animation of the
// authored box — the model itself is untouched. Disabled for reduced motion.
function updateAdoptionBoxBounce(now) {
  const state = protocol.getState();
  const room = descriptor?.rooms?.living;
  const adoption = room?.adoption || {};
  const active = state.mode === 'adoption' && !state.adoptionOpen && !state.reducedMotion;
  const scene = adoptionRoot || roomRoot;
  const box = scene ? findNode(scene, adoption.boxNode || 'PROP__living__adoption_box') : null;
  if (!box) return;
  if (!box.userData.bounceBase) {
    box.userData.bounceBase = {
      y: box.position.y,
      rz: box.rotation.z,
      rx: box.rotation.x,
      ry: box.rotation.y,
    };
  }
  const base = box.userData.bounceBase;
  if (!active) {
    if (box.position.y !== base.y) box.position.y = base.y;
    if (box.rotation.z !== base.rz) box.rotation.z = base.rz;
    if (box.rotation.x !== base.rx) box.rotation.x = base.rx;
    if (box.rotation.y !== base.ry) box.rotation.y = base.ry;
    return;
  }
  // Раз в ~2.6 с коробка подпрыгивает и на лету потряхивается вбок и вокруг вертикальной оси.
  const period = 2600;
  const phase = (now % period) / period;
  const jumpWindow = 0.28;
  const u = phase < jumpWindow ? phase / jumpWindow : -1;
  const hop = u >= 0 ? Math.sin(u * Math.PI) : 0;
  box.position.y = base.y + hop * 0.14;
  box.rotation.z = base.rz + (u >= 0 ? Math.sin(u * Math.PI * 5) * 0.11 * hop : 0);
  box.rotation.x = base.rx + (u >= 0 ? Math.sin(u * Math.PI * 4 + 1) * 0.05 * hop : 0);
  box.rotation.y = base.ry + (u >= 0 ? Math.sin(u * Math.PI * 3) * 0.2 * hop : 0);
}

function renderFrame(now) {
  frameHandle = 0;
  if (isRuntimePaused() || contextLost || !renderer) return;
  // Android WebView may update the CSS viewport a frame after its resize
  // event. Keep the WebGL buffer in step with the actual canvas dimensions.
  if (canvas.clientWidth !== renderedCssWidth ||
      canvas.clientHeight !== renderedCssHeight) resize();
  const deltaSeconds = Math.min(clock.getDelta(), 0.1);
  clearHeadAimPose();
  reconcilePetIdle();
  if (petMixer) petMixer.update(deltaSeconds);
  petGrowth?.update(deltaSeconds);
  updateContactCue();
  applyHeadAimPose();
  updateContactPropMotion();
  updateTween(now);
  updateCameraTween(now);
  updateRoomCurtain(deltaSeconds);
  updateAdoptionBoxBounce(now);
  dishFoam.update(deltaSeconds);
  dishWater?.update(deltaSeconds);
  const dishState = dishRound.getState();
  const dishStage = dishState.stage;
  if (dishState.waterOn) runtimeAudio.contact('waterFlow');
  if (dishStage === 'rinse') {
    const foam = dishFoam.diagnostics();
    const peak = Math.max(1, foam.foamPeak || foam.foamCount || 1);
    const progress = Math.max(dishRinseProgress, dishRinsedFoam / peak, 1 - foam.foamCount / peak);
    if (progress > dishRinseProgress) {
      dishRinseProgress = progress;
      updateDishView();
      emitDishCoverageProgress();
    }
    if (dishRinseProgress >= DISH_RINSE_THRESHOLD && foam.rinseSamples >= 3) dishStep('rinse');
  }
  if (petAccessory && petModel) {
    petModel.updateMatrixWorld(true);
    updatePetAccessory(petAccessory);
  }
  if (now - lastFrameAt >= TARGET_FRAME_MS) {
    scheduleShadowRefresh(now);
    renderer.render(scene, camera);
    lastFrameAt = now;
    if (qualityController.recordRenderedFrame(now, { active: !anyMinigameActive() })) {
      applyCurrentGraphicsQuality();
    }
  }
  scheduleFrame();
}

// Point-light shadows redraw every caster into six cube faces, so on weaker
// tiers they refresh a few times per second instead of on every frame.
const SHADOW_REFRESH_MS = Object.freeze({ low: 125, standard: 66, high: 0 });
let lastShadowAt = -Infinity;
function scheduleShadowRefresh(now) {
  const shadowMap = renderer?.shadowMap;
  if (!shadowMap?.enabled) return;
  const refreshMs = SHADOW_REFRESH_MS[qualityController.getState().tier] ?? 0;
  shadowMap.autoUpdate = refreshMs === 0;
  if (refreshMs && now - lastShadowAt >= refreshMs) {
    shadowMap.needsUpdate = true;
    lastShadowAt = now;
  }
}

// Immediate redraw after a state change. While the frame loop runs, it already
// shows the change within one 30 FPS frame, so extra draws (tween ticks at the
// display rate, pointer moves) are skipped instead of doubling the GPU work.
function renderNow() {
  const now = performance.now();
  if (frameHandle && !isRuntimePaused() && now - lastFrameAt < TARGET_FRAME_MS) {
    // Callers rely on render() refreshing world matrices synchronously.
    scene.updateMatrixWorld();
    if (camera.parent === null) camera.updateMatrixWorld();
    return;
  }
  scheduleShadowRefresh(now);
  renderer.render(scene, camera);
  lastFrameAt = now;
}

function isRuntimePaused() {
  return paused || visibilityPaused || contextLost;
}

function updatePauseLoop() {
  if (isRuntimePaused()) {
    if (frameHandle) cancelAnimationFrame(frameHandle);
    frameHandle = 0;
    if (activeTween) activeTween.lastAt = null;
    if (cameraTween) cameraTween.lastAt = null;
    clock.stop();
  } else if (!contextLost) {
    lastFrameAt = 0;
    clock.start();
    resize();
    scheduleFrame();
  }
}

function setPaused(value) {
  paused = Boolean(value);
  if (paused) {
    qualityController.resetSamples();
    accessibleMinigameToken += 1;
    if (dishRound.getState().stage !== 'idle') pauseDishSpongeMotion();
    cancelActiveJobClothFold(false);
    if (jobPointer?.kind !== 'fold') restoreJobGesture(jobPointer);
    if (dishPointer) restoreDishGesture(dishPointer);
    jobPointer = null;
    dishPointer = null;
    dishFoam.breakStroke();
    cancelNavigation('paused');
    cancelActiveContact('paused');
    cancelPetReaction('paused');
    dialogueBottomFraction = 0;
    dialogueFaceNdcY = null;
    previewFramingFocus = null;
    previewBottomFraction = 0;
    previewTargetNdcY = null;
    if (descriptor && roomRoot && currentRoomId) configureCurrentCamera();
  } else if (!isRuntimePaused()) {
    if (['scrub', 'rinse'].includes(dishRound.getState().stage) &&
        !dishSpongeLogicalContact && !dishSpongeParked && !dishSpongeParkingActive) {
      void beginDishSpongeParking();
    } else if (dishSpongeLogicalContact) dishSpongeMotionPhase = 'contact';
    else if (dishSpongeParked) dishSpongeMotionPhase = 'parked';
  }
  runtimeAudio.setPaused(isRuntimePaused() || contextLost);
  dishFoam.setPaused(isRuntimePaused() || contextLost);
  dishWater?.setPaused(isRuntimePaused() || contextLost);
  updatePauseLoop();
  if (!isRuntimePaused()) recoverDishRinseAfterInterruption();
  return { paused };
}

function setSoundEnabled(value) {
  return runtimeAudio.setEnabled(value);
}

function setSoundVolume(value) {
  return runtimeAudio.setVolume(value);
}

function playAudioCue(cue) {
  return runtimeAudio.play(cue);
}

function disposeAudio() {
  return runtimeAudio.dispose();
}

function disposeMaterial(material) {
  if (!material) return;
  for (const key of Object.keys(material)) {
    const value = material[key];
    if (value?.isTexture) value.dispose();
  }
  material.dispose?.();
}

function disposeObject(root) {
  if (!root) return;
  root.traverse((object) => {
    if (object.geometry) object.geometry.dispose();
    if (Array.isArray(object.material)) object.material.forEach(disposeMaterial);
    else if (object.material) disposeMaterial(object.material);
    object.customDepthMaterial?.dispose?.();
    object.customDistanceMaterial?.dispose?.();
  });
}

function releaseContextResources() {
  // Three r160 recreates its WebGL managers after a context restore, but the
  // old managers remain subscribed to resources that have already rendered.
  // Dispose only their GPU bindings while the context is lost; the CPU scene
  // graph and minigame state stay intact and are uploaded on the next render.
  const released = new Set();
  const release = (resource) => {
    if (!resource?.dispose || released.has(resource)) return;
    released.add(resource);
    resource.dispose();
  };
  const releaseTextureValue = (value) => {
    if (value?.isTexture) release(value);
    else if (Array.isArray(value)) value.forEach((entry) => {
      if (entry?.isTexture) release(entry);
    });
  };
  const releaseMaterial = (material) => {
    if (!material || released.has(material)) return;
    for (const value of Object.values(material)) releaseTextureValue(value);
    for (const uniform of Object.values(material.uniforms || {})) releaseTextureValue(uniform?.value);
    release(material);
  };
  scene.traverse((object) => {
    release(object.geometry);
    release(object.skeleton?.boneTexture);
    if (Array.isArray(object.material)) object.material.forEach(releaseMaterial);
    else releaseMaterial(object.material);
    releaseMaterial(object.customDepthMaterial);
    releaseMaterial(object.customDistanceMaterial);
    release(object.shadow?.map);
    release(object.shadow?.mapPass);
  });
  release(scene.background?.isTexture ? scene.background : null);
  release(scene.environment?.isTexture ? scene.environment : null);
  for (const material of materialClones) releaseMaterial(material);
  return released.size;
}

function clearGroup(group, dispose = true) {
  while (group.children.length) {
    const child = group.children.pop();
    if (dispose) disposeObject(child);
  }
}

function findNode(root, name) {
  return name && root ? root.getObjectByName(name) : null;
}

function nodeWorldPosition(root, reference, fallback = [0, 0, 0]) {
  if (typeof reference === 'string') {
    const node = findNode(root, reference);
    if (node) return node.getWorldPosition(new THREE.Vector3());
  }
  if (reference && typeof reference === 'object' && typeof reference.node === 'string') {
    const node = findNode(root, reference.node);
    if (node) return node.getWorldPosition(new THREE.Vector3());
    if (reference.position) return vec3(reference.position, fallback);
  }
  return vec3(reference, fallback);
}

function roomActions(room) {
  if (Array.isArray(room.actions)) return room.actions;
  if (room.actions && typeof room.actions === 'object') {
    return Object.entries(room.actions).map(([id, action]) => ({ id, ...action }));
  }
  return [];
}

function roomInteractives(room) {
  if (Array.isArray(room.interactives)) return room.interactives;
  if (room.interactives && typeof room.interactives === 'object') {
    return Object.entries(room.interactives).map(([id, interactive]) => ({ id, ...interactive }));
  }
  return [];
}

function roomDoors(room) {
  if (Array.isArray(room.doors)) return room.doors;
  if (room.doors && typeof room.doors === 'object') {
    return Object.entries(room.doors).map(([id, door]) => ({ id, ...door }));
  }
  return [];
}

function normalizeActionId(action, state = protocol.getState()) {
  if (action === 'clean') return state.species === 'hamster' ? 'clean_sand' : 'clean_water';
  if (action === 'stars') return 'goal_stars';
  return action;
}

function bridgeAction(actionId) {
  if (typeof actionId !== 'string') return null;
  if (/^job_j0[1-6]$/.test(actionId)) return actionId;
  if (actionId === 'wash_dishes' || actionId.includes('dish_sink')) return 'wash_dishes';
  if (actionId === 'clean_water' || actionId === 'clean_sand' || actionId.includes('bathtub') || actionId.includes('sand_bath')) return 'clean';
  if (actionId === 'feed' || actionId.includes('food_bowl')) return 'feed';
  if (actionId === 'play' || actionId.includes('ball')) return 'play';
  if (actionId === 'goal_stars' || actionId === 'stars') return 'stars';
  if (actionId === 'nightlight') return 'nightlight';
  if (actionId === 'room') return 'room';
  return null;
}

function inferredAdoptionCamera(room) {
  const adoption = room.adoption || {};
  const box = findNode(adoptionRoot || roomRoot, adoption.boxNode || 'PROP__living__adoption_box');
  if (!box) return null;
  const bounds = new THREE.Box3().setFromObject(box);
  if (bounds.isEmpty()) return null;
  const center = bounds.getCenter(new THREE.Vector3());
  const height = Math.max(1.35, bounds.max.y - bounds.min.y + petScaleMeters(protocol.getState().species) + 0.28);
  const target = center.clone();
  target.y = bounds.min.y + height * 0.48;
  const fovDegrees = 34;
  const distance = Math.max(2, (height * 0.62) / Math.tan(THREE.MathUtils.degToRad(fovDegrees / 2)));
  return {
    position: [target.x, target.y + 0.12, target.z + distance],
    target: target.toArray(),
    fovDegrees,
    near: 0.05,
    far: 30,
  };
}

function configureCamera(room) {
  const state = protocol.getState();
  // Use the authored interior camera that is checked with the room assets.
  // HUD insets never zoom the room out.
  const spec = state.mode === 'home'
    ? room.camera
    : room.adoption?.camera || inferredAdoptionCamera(room) || room.camera;
  camera.position.copy(vec3(spec.position, [0, 2.4, 5.5]));
  camera.fov = responsiveVerticalFov(Number.isFinite(spec.fovDegrees) ? spec.fovDegrees : 38);
  camera.near = Number.isFinite(spec.near) ? spec.near : 0.05;
  camera.far = Number.isFinite(spec.far) ? spec.far : 80;
  const target = vec3(state.mode === 'home' && camera.aspect > 1 && spec.landscapeTarget
    ? spec.landscapeTarget : spec.target, [0, 1, 0]);
  camera.lookAt(target);
  camera.updateProjectionMatrix();
  if (roomCurtain.visible) setRoomCurtainOpacity(roomCurtain.material.opacity);
  if (previewFramingFocus && previewBottomFraction > 0 && state.mode === 'home' && !activeContact) {
    applyPreviewFraming(room, previewFramingFocus);
  } else if (dialogueBottomFraction > 0 && state.mode === 'home' && !activeContact && petModel) {
    applyDialogueFraming(room, target);
  }
  positionDishCloseup();
}

function responsiveVerticalFov(baseFov) {
  if (camera.aspect <= 1) return baseFov;
  // Landscape keeps rendering edge-to-edge and gains horizontal world view,
  // while a modest vertical crop avoids looking beyond authored side walls.
  const landscape = THREE.MathUtils.clamp((camera.aspect - 1) / 1.1, 0, 1);
  return baseFov * THREE.MathUtils.lerp(1, 0.86, landscape);
}

function configureCurrentCamera() {
  const state = protocol.getState();
  if (dishRound.getState().stage !== 'idle') {
    configureJobCamera('wash_dishes');
  } else if (genericJobActive()) {
    configureJobCamera(`job_${jobRound.getState().jobId.toLowerCase()}`);
  } else {
    const room = roomDefinition(currentRoomId);
    if (!room) return;
    configureCamera(room);
    if (state.mode === 'adoption' && state.adoptionOpen) configureOpenAdoptionCamera(room);
  }
}

function applyDialogueFraming(room, baseTarget = vec3(room?.camera?.target, [0, 1, 0])) {
  if (!petModel || dialogueBottomFraction <= 0) return null;
  const petBounds = exactModelBounds(petLayer);
  if (petBounds.isEmpty()) return null;
  const face = petBounds.getCenter(new THREE.Vector3());
  face.y = petBounds.max.y - petBounds.getSize(new THREE.Vector3()).y * 0.12;
  const desiredNdcY = THREE.MathUtils.lerp(0.34, 0.72, dialogueBottomFraction / 0.7);
  // The search window reaches past the authored target both ways: with the
  // wider default framing a small pet (hamster) otherwise sits too low for the
  // bisection to lift its face above a tall dialogue panel.
  let low = baseTarget.y - 4.0;
  let high = baseTarget.y + 1.2;
  const target = baseTarget.clone();
  for (let index = 0; index < 18; index += 1) {
    target.y = (low + high) * 0.5;
    camera.lookAt(target);
    camera.updateMatrixWorld(true);
    const projectedY = face.clone().project(camera).y;
    if (projectedY > desiredNdcY) low = target.y;
    else high = target.y;
  }
  target.y = (low + high) * 0.5;
  camera.lookAt(target);
  camera.updateMatrixWorld(true);
  dialogueFaceNdcY = +face.clone().project(camera).y.toFixed(4);
  return dialogueFaceNdcY;
}

function setDialogueFraming(bottomFraction = 0) {
  const value = bottomFraction === false || bottomFraction === null ? 0 : Number(bottomFraction);
  if (!Number.isFinite(value) || value < 0 || value > 0.7) return { ok: false, reason: 'invalid_fraction' };
  if (activeContact || anyMinigameActive() || protocol.getPending()) return { ok: false, reason: 'busy' };
  previewFramingFocus = null;
  previewBottomFraction = 0;
  previewTargetNdcY = null;
  dialogueBottomFraction = value;
  dialogueFaceNdcY = null;
  const room = roomDefinition(currentRoomId);
  if (room) configureCamera(room);
  if (renderer) renderer.render(scene, camera);
  return { ok: true, bottomFraction: dialogueBottomFraction, faceNdcY: dialogueFaceNdcY };
}

function previewFramingObject(focus) {
  const nodes = {
    bed: 'PROP__living__cozy_bed',
    house: 'PROP__living__goal_house',
    garden: 'PROP__kitchen__goal_garden',
    stars: 'PROP__living__goal_stars',
    nightlight: 'PROP__living__nightlight',
    ball: 'PROP__living__ball',
  };
  return focus === 'pet' ? petLayer : findNode(roomRoot, nodes[focus]);
}

function previewFramingBounds(object) {
  const box = object === petLayer ? exactModelBounds(object) : new THREE.Box3().setFromObject(object);
  if (object === petLayer && petAccessory) {
    petAccessory.updateWorldMatrix(true, true);
    const accessoryBounds = new THREE.Box3().setFromObject(petAccessory);
    if (!accessoryBounds.isEmpty()) box.union(accessoryBounds);
  }
  return box;
}

function applyPreviewFraming(room, focus) {
  const object = previewFramingObject(focus);
  if (!object?.visible || previewBottomFraction <= 0) return null;
  const box = previewFramingBounds(object);
  if (box.isEmpty()) return null;
  const center = box.getCenter(new THREE.Vector3());
  if (focus === 'pet') center.y = box.max.y - box.getSize(new THREE.Vector3()).y * 0.12;
  const desiredNdcY = THREE.MathUtils.lerp(0.28, 0.58, previewBottomFraction / 0.7);
  let low = center.y - 3.2;
  let high = center.y;
  const target = center.clone();
  for (let index = 0; index < 20; index += 1) {
    target.y = (low + high) * 0.5;
    camera.lookAt(target);
    camera.updateMatrixWorld(true);
    const projectedY = center.clone().project(camera).y;
    if (projectedY > desiredNdcY) low = target.y;
    else high = target.y;
  }
  target.y = (low + high) * 0.5;
  camera.lookAt(target);
  camera.updateMatrixWorld(true);
  previewTargetNdcY = +center.clone().project(camera).y.toFixed(4);
  return previewTargetNdcY;
}

function setPreviewFraming(request = false) {
  if (activeContact || anyMinigameActive() || protocol.getPending()) return { ok: false, reason: 'busy' };
  if (request === false || request === null) {
    previewFramingFocus = null;
    previewBottomFraction = 0;
    previewTargetNdcY = null;
  } else {
    if (!request || typeof request !== 'object') return { ok: false, reason: 'invalid_request' };
    const focus = request.focus;
    const bottomFraction = Number(request.bottomFraction);
    if (!['pet', 'bed', 'house', 'garden', 'stars', 'nightlight', 'ball'].includes(focus)) {
      return { ok: false, reason: 'invalid_focus' };
    }
    if (!Number.isFinite(bottomFraction) || bottomFraction < 0 || bottomFraction > 0.7) {
      return { ok: false, reason: 'invalid_fraction' };
    }
    previewFramingFocus = focus;
    previewBottomFraction = bottomFraction;
    previewTargetNdcY = null;
    dialogueBottomFraction = 0;
    dialogueFaceNdcY = null;
  }
  const room = roomDefinition(currentRoomId);
  if (room) configureCamera(room);
  if (renderer) renderer.render(scene, camera);
  const object = previewFramingFocus ? previewFramingObject(previewFramingFocus) : null;
  if (previewFramingFocus && (!object || !object.visible)) return {
    ok: false, reason: 'focus_unavailable', focus: previewFramingFocus, bottomFraction: previewBottomFraction,
  };
  return { ok: true, focus: previewFramingFocus, bottomFraction: previewBottomFraction, targetNdcY: previewTargetNdcY };
}

function configureOpenAdoptionCamera(room) {
  // Box and landing positions are staged for this interior portrait camera.
  // Pulling back to fit their bounds would expose the outside of the room.
  configureCamera(room);
}
function petScaleMeters(species) {
  const value = descriptor?.petScaleMeters;
  if (Number.isFinite(value)) return value;
  if (value && Number.isFinite(value[species])) return value[species];
  return species === 'hamster' ? 0.34 : 0.62;
}

function exactModelBounds(model) {
  model.updateMatrixWorld(true);
  const bounds = new THREE.Box3();
  const point = new THREE.Vector3();
  model.traverse((object) => {
    if (!object.isMesh || !object.geometry) return;
    const position = object.geometry.getAttribute('position');
    if (!position) return;
    for (let index = 0; index < position.count; index += 1) {
      if (object.isSkinnedMesh) object.getVertexPosition(index, point);
      else point.fromBufferAttribute(position, index);
      point.applyMatrix4(object.matrixWorld);
      bounds.expandByPoint(point);
    }
  });
  return bounds;
}

function normalizePetModel(model, species, animations = []) {
  model.updateMatrixWorld(true);
  const defaultBounds = exactModelBounds(model);
  const defaultHeight = defaultBounds.getSize(new THREE.Vector3()).y;
  const idle = animations.find((clip) => clip.name === `${species}_idle` || clip.name === 'idle');
  let baselineMixer = null;
  let baselineAction = null;
  if (idle) {
    baselineMixer = new THREE.AnimationMixer(model);
    baselineAction = baselineMixer.clipAction(idle);
    baselineAction.reset().setLoop(THREE.LoopOnce, 1).play();
    baselineMixer.setTime(0);
  }
  model.updateMatrixWorld(true);
  const initial = exactModelBounds(model);
  const size = initial.getSize(new THREE.Vector3());
  const height = Math.max(size.y, 0.0001);
  const intendedHeight = petScaleMeters(species);
  model.scale.setScalar(intendedHeight / height);
  model.updateMatrixWorld(true);
  const scaled = exactModelBounds(model);
  const center = scaled.getCenter(new THREE.Vector3());
  model.position.x -= center.x;
  model.position.z -= center.z;
  model.position.y -= scaled.min.y;
  baselineAction?.stop();
  baselineMixer?.stopAllAction();
  baselineMixer?.update(0);
  model.updateMatrixWorld(true);
  model.userData.runtimeNormalization = {
    species,
    defaultHeightMeters: +defaultHeight.toFixed(7),
    idle0HeightMeters: +height.toFixed(7),
    intendedHeightMeters: +intendedHeight.toFixed(7),
    uniformScale: +model.scale.x.toFixed(7),
    normalizedIdle0HeightMeters: +(height * model.scale.x).toFixed(7),
  };
}

function tintFor(species, color) {
  const palette = {
    kitten: { fur_01: 0xffffff, fur_02: 0xd8d0c5, fur_03: 0xb88464 },
    puppy: { fur_01: 0xffffff, fur_02: 0xe0c79f, fur_03: 0xa97e64 },
    hamster: { fur_01: 0xffffff, fur_02: 0xe6d5bc, fur_03: 0xb9a99a },
  };
  return palette[species]?.[color] ?? 0xffffff;
}

function applyPetTint(root, species, color) {
  const tint = new THREE.Color(tintFor(species, color));
  const canonicalCoat = /^fur_0[1-3]$/.test(color);
  root.traverse((object) => {
    if (!object.isMesh || !object.material) return;
    const source = Array.isArray(object.material) ? object.material : [object.material];
    const clones = source.map((material) => {
      const clone = material.clone();
      // Material.clone() copies values but intentionally resets shader hooks.
      // Preserve the runtime8 skinning and optional facial crease programs.
      clone.onBeforeCompile = material.onBeforeCompile;
      clone.customProgramCacheKey = material.customProgramCacheKey;
      if (!canonicalCoat && clone.color) clone.color.multiply(tint);
      materialClones.add(clone);
      return clone;
    });
    object.material = Array.isArray(object.material) ? clones : clones[0];
    object.castShadow = false;
    object.receiveShadow = false;
  });
  if (!canonicalCoat) {
    diagnostic('PROCEDURAL_COLOR_PREVIEW', { species, color, message: 'Tint preview is not a final authored fur material.' });
  }
}

function modelFileFor(state) {
  const previewFile = petPreview
    ? descriptor?.candidatePetModels?.[petPreview]?.[state.species]
    : null;
  if (typeof previewFile === 'string' && /^[a-z0-9_.-]+$/i.test(previewFile)) return previewFile;
  const accessoryBase = state.wearable ? descriptor?.runtimeAccessoryPetModels?.[state.species] : null;
  if (typeof accessoryBase === 'string' && /^[a-z0-9_.-]+$/i.test(accessoryBase)) return accessoryBase;
  // Default: rigged service models with full clip sets, blink and growth morphs.
  // Static *-mobile.glb remain the fallback if the descriptor is unavailable.
  const rigged = descriptor?.candidatePetModels?.[DEFAULT_PET_SET]?.[state.species];
  if (typeof rigged === 'string' && /^[a-z0-9_.-]+$/i.test(rigged)) return rigged;
  const base = MODEL_FILES[state.species];
  return `${base}-mobile.glb`;
}

function petActionContactSpec(action, state = protocol.getState()) {
  return descriptor?.petActionContacts?.[normalizeActionId(action, state)] || null;
}

function petActionClip(spec, state = protocol.getState()) {
  if (!spec?.clip) return null;
  return petClips.get(`${state.species}_${spec.clip}`) || petClips.get(spec.clip) || null;
}

function actionContactDiagnostics() {
  const materialProgramKeys = new Set();
  petModel?.traverse((object) => {
    if (!object.isMesh || !object.material) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    for (const material of materials) materialProgramKeys.add(material.customProgramCacheKey());
  });
  const scenarioProp = activeContact?.spec?.propNode ? findNode(roomRoot, activeContact.spec.propNode) : null;
  const bounds = (object) => {
    if (!object) return null;
    const box = object === petLayer ? exactModelBounds(object) : new THREE.Box3().setFromObject(object);
    return {
      min: box.min.toArray().map((value) => +value.toFixed(4)),
      max: box.max.toArray().map((value) => +value.toFixed(4)),
      center: box.getCenter(new THREE.Vector3()).toArray().map((value) => +value.toFixed(4)),
      size: box.getSize(new THREE.Vector3()).toArray().map((value) => +value.toFixed(4)),
    };
  };
  const projectedBounds = (object) => {
    if (!object) return null;
    const box = previewFramingBounds(object);
    if (box.isEmpty()) return null;
    camera.updateMatrixWorld(true);
    const projected = [];
    for (const x of [box.min.x, box.max.x]) for (const y of [box.min.y, box.max.y]) {
      for (const z of [box.min.z, box.max.z]) projected.push(new THREE.Vector3(x, y, z).project(camera));
    }
    return {
      minX: +Math.min(...projected.map((point) => point.x)).toFixed(4),
      maxX: +Math.max(...projected.map((point) => point.x)).toFixed(4),
      minY: +Math.min(...projected.map((point) => point.y)).toFixed(4),
      maxY: +Math.max(...projected.map((point) => point.y)).toFixed(4),
    };
  };
  const previewTargets = {
    pet: petLayer,
    bed: findNode(roomRoot, 'PROP__living__cozy_bed'),
    house: findNode(roomRoot, 'PROP__living__goal_house'),
    garden: findNode(roomRoot, 'PROP__kitchen__goal_garden'),
    stars: findNode(roomRoot, 'PROP__living__goal_stars'),
    nightlight: findNode(roomRoot, 'PROP__living__nightlight'),
    ball: findNode(roomRoot, 'PROP__living__ball'),
  };
  return {
    preview: petPreview || null,
    candidateFile: descriptor ? modelFileFor(protocol.getState()) : null,
    normalization: petModel?.userData?.runtimeNormalization
      ? { ...petModel.userData.runtimeNormalization } : null,
    accessory: petAccessory?.userData?.petAccessory
      ? { ...petAccessory.userData.petAccessory, separateAsset: true } : null,
    dialogueFraming: { bottomFraction: dialogueBottomFraction, faceNdcY: dialogueFaceNdcY },
    previewFraming: { focus: previewFramingFocus, bottomFraction: previewBottomFraction, targetNdcY: previewTargetNdcY },
    optionalFixtures: (roomDefinition()?.optionalFixtures || []).map((spec) => {
      const node = roomRoot?.getObjectByName(spec.node);
      const nodeBounds = bounds(node);
      const centerNdc = nodeBounds
        ? new THREE.Vector3(...nodeBounds.center).project(camera).toArray().map((value) => +value.toFixed(4)) : null;
      return { id: spec.id, visible: node?.visible === true, bounds: nodeBounds, centerNdc,
        supportHeight: Number.isFinite(node?.userData?.supportHeight) ? +node.userData.supportHeight.toFixed(4) : null };
    }),
    previewTargets: Object.fromEntries(Object.entries(previewTargets).map(([id, object]) => [id, object ? {
      visible: object.visible === true,
      bounds: bounds(object),
      screen: projectedBounds(object),
    } : null])),
    growth: petGrowth?.diagnostics() || null,
    petPosition: petLayer.position.toArray().map((value) => +value.toFixed(4)),
    homePosition: petHome.toArray().map((value) => +value.toFixed(4)),
    petYawRadians: +petLayer.rotation.y.toFixed(4),
    cameraPosition: camera.position.toArray().map((value) => +value.toFixed(4)),
    clips: [...petClips.keys()],
    materialProgramKeys: [...materialProgramKeys],
    movement: activeTween ? {
      tag: activeTween.tag,
      distanceMeters: +activeTween.from.distanceTo(activeTween.to).toFixed(4),
      durationMs: +activeTween.duration.toFixed(1),
      elapsedMs: +activeTween.elapsedMs.toFixed(1),
      phase: activeTween.locomotion?.phase || null,
      clipTimeScale: activeTween.locomotion?.timeScale || null,
    } : null,
    roomTransition: { opacity: +roomCurtain.material.opacity.toFixed(3),
      actionId: roomCurtainActionId,
      cameraFov: +camera.fov.toFixed(3),
      horizontalCoverage: +(roomCurtain.scale.x / (0.2 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * camera.aspect)).toFixed(3),
      verticalCoverage: +(roomCurtain.scale.y / (0.2 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)))).toFixed(3) },
    locomotion: lastLocomotionDiagnostics ? { ...lastLocomotionDiagnostics } : null,
    reaction: activeReaction ? {
      kind: activeReaction.kind,
      serial: activeReaction.serial,
      clip: activeReaction.clip.name,
      phase: activeReaction.action.time / Math.max(activeReaction.clip.duration, 0.001),
    } : null,
    active: activeContact ? {
      id: activeContact.id,
      action: activeContact.action,
      clip: activeContact.clip?.name || null,
      cancelled: activeContact.cancelled,
      phase: activeContact.petAction && activeContact.clip
        ? activeContact.petAction.time / activeContact.clip.duration : 0,
      petPosition: petLayer.position.toArray().map((value) => +value.toFixed(4)),
      petRotationY: +petLayer.rotation.y.toFixed(4),
      petBounds: bounds(petLayer),
      propBounds: bounds(scenarioProp),
    } : null,
    last: lastContactDiagnostics ? { ...lastContactDiagnostics } : null,
  };
}

function lightingDiagnostics() {
  const lighting = roomLighting?.diagnostics();
  return lighting ? { ...lighting, renderer: rendererDiagnostics() } : null;
}

function roomDefinition(id = effectiveRoom()) {
  return descriptor?.rooms?.[id] || null;
}

function effectiveRoom(state = protocol.getState()) {
  return state.mode === 'adoption' ? 'living' : state.room;
}

function currentJobId(state = protocol.getState()) {
  if (state.selectedJobId && JOB_DEFINITIONS[state.selectedJobId]) return state.selectedJobId;
  const period = Math.max(1, Math.min(6, Math.trunc(Number(state.jobPeriod) || 1)));
  return `J${String(period).padStart(2, '0')}`;
}

function adoptionSpawnPosition(room) {
  const adoption = room.adoption || {};
  const explicit = adoption.petSpawn || adoption.spawnNode || 'ANCHOR__living__adoption_pet_spawn';
  const adoptionScene = adoptionRoot || roomRoot;
  const explicitNode = nodeReferenceName(explicit) ? findNode(adoptionScene, nodeReferenceName(explicit)) : null;
  if (explicitNode) return explicitNode.getWorldPosition(new THREE.Vector3());
  if (explicit?.roomPosition) return vec3(explicit.roomPosition);
  if (explicit?.localPosition && adoptionRoot) return adoptionRoot.localToWorld(vec3(explicit.localPosition));
  const box = findNode(adoptionScene, adoption.boxNode || 'PROP__living__adoption_box');
  return box
    ? box.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 0.32, 0))
    : nodeWorldPosition(roomRoot, room.petSpawn || 'ANCHOR__pet_spawn');
}

function adoptionLandingPosition(room) {
  const adoption = room.adoption || {};
  if (adoption.petLanding?.roomPosition) return vec3(adoption.petLanding.roomPosition);
  const box = findNode(adoptionRoot || roomRoot, adoption.boxNode || 'PROP__living__adoption_box');
  if (!box) return adoptionSpawnPosition(room);
  const bounds = new THREE.Box3().setFromObject(box);
  const petSize = petModel
    ? new THREE.Box3().setFromObject(petModel).getSize(new THREE.Vector3())
    : new THREE.Vector3(0.4, petScaleMeters(protocol.getState().species), 0.4);
  return new THREE.Vector3(
    bounds.max.x + petSize.x * 0.5 + 0.12,
    Number.isFinite(room.floor?.height) ? room.floor.height : 0,
    bounds.max.z + petSize.z * 0.5 + 0.12,
  );
}

function placePetAtSpawn(room = roomDefinition()) {
  if (!room || !roomRoot) return;
  const state = protocol.getState();
  if (state.mode === 'adoption') {
    petHome = state.adoptionOpen ? adoptionLandingPosition(room) : adoptionSpawnPosition(room);
  } else {
    petHome = room.petSpawn?.position
      ? vec3(room.petSpawn.position)
      : nodeWorldPosition(roomRoot, room.petSpawn || 'ANCHOR__pet_spawn');
  }
  petHome.y = standingHeight(petHome);
  petLayer.position.copy(petHome);
  facePetToCamera();
}

function standingHeight(point) {
  const floor = roomDefinition()?.floor?.height ?? 0;
  if (!roomRoot) return floor;
  roomRoot.updateWorldMatrix(true, true);
  // Sample the actual rug/floor under the paws, below furniture height.
  // Only endpoints are sampled; no triangle raycast runs in the frame loop.
  const groundRay = new THREE.Raycaster();
  let height = floor;
  for (const [x, z] of [[0, 0], [-0.12, 0.12], [0.12, 0.12]]) {
    groundRay.set(new THREE.Vector3(point.x + x, floor + 0.35, point.z + z), new THREE.Vector3(0, -1, 0));
    groundRay.far = 0.36;
    const hit = groundRay.intersectObject(roomRoot, true)[0];
    if (hit) height = Math.max(height, hit.point.y);
  }
  return height + 0.006;
}

function nodeReferenceName(reference) {
  if (typeof reference === 'string') return reference;
  return reference && typeof reference.node === 'string' ? reference.node : null;
}

async function updateAdoptionVisual(animateOpen = false) {
  const token = ++adoptionVisualToken;
  const state = protocol.getState();
  const room = descriptor?.rooms?.living;
  const adoption = room?.adoption || {};
  const asset = descriptor?.assets?.[adoption.asset] || {};
  const inAdoption = state.mode === 'adoption';
  interactionLayer.visible = !inAdoption;
  adoptionLayer.visible = inAdoption;
  if (activeContact?.action === 'box_emerge') cancelActiveContact('adoption_state_changed');
  if (activeTween?.tag === 'adoption') {
    const interrupted = activeTween;
    activeTween = null;
    interrupted.resolve();
  }

  const adoptionScene = adoptionRoot || roomRoot;
  const box = findNode(adoptionScene, adoption.boxNode || 'PROP__living__adoption_box');
  const lid = findNode(adoptionScene, adoption.lidNode || 'PROP__living__adoption_lid');
  const openStateNodes = adoption.openStateNodes || {};
  const closed = findNode(adoptionScene, adoption.closedNode || openStateNodes.closed);
  const open = findNode(adoptionScene, adoption.openNode || openStateNodes.open);
  if (box) box.visible = inAdoption;
  if (closed) closed.visible = inAdoption && !state.adoptionOpen;
  if (open) open.visible = inAdoption && state.adoptionOpen;
  if (lid) {
    if (!lid.userData.runtimeAuthoredRotation) lid.userData.runtimeAuthoredRotation = lid.rotation.clone();
    const angle = THREE.MathUtils.degToRad(Number.isFinite(adoption.lidOpenRotationDegrees) ? adoption.lidOpenRotationDegrees : -72);
    const authoredOpen = (adoption.authoredState || asset.authoredState) === 'open';
    const closedSupported = (adoption.closedStateSupported ?? asset.closedStateSupported) !== false;
    const offset = !closedSupported
      ? 0
      : authoredOpen
        ? (state.adoptionOpen ? 0 : -angle)
        : (state.adoptionOpen ? angle : 0);
    lid.rotation.x = lid.userData.runtimeAuthoredRotation.x + offset;
    if (!lid.userData.runtimeAuthoredPosition) lid.userData.runtimeAuthoredPosition = lid.position.clone();
    lid.position.copy(lid.userData.runtimeAuthoredPosition);
    if (closedSupported && authoredOpen && !state.adoptionOpen && Array.isArray(adoption.lidClosedOffset)) {
      lid.position.add(vec3(adoption.lidClosedOffset, [0, 0, 0]));
    }
    if (inAdoption && !state.adoptionOpen && !closedSupported && !warnedOpenOnlyBox) {
      warnedOpenOnlyBox = true;
      diagnostic('ADOPTION_BOX_OPEN_ONLY', { message: 'The authored hollow box has no validated closed state; it remains open before selection.' });
    }
  }

  petLayer.visible = !inAdoption || state.adoptionOpen;
  if (!petLayer.visible || !petModel) return;
  placePetAtSpawn(roomDefinition(effectiveRoom(state)));
  if (inAdoption && state.adoptionOpen) configureOpenAdoptionCamera(room);
  if (!animateOpen || state.reducedMotion) {
    if (inAdoption && state.adoptionOpen) facePetToCamera();
    return;
  }
  const landing = petHome.clone();
  const spawn = adoptionSpawnPosition(room);
  const start = spawn.clone().add(new THREE.Vector3(0, -0.12, 0));
  const jumpPeak = Number.isFinite(adoption.petSpawn?.jumpPeakMeters) ? adoption.petSpawn.jumpPeakMeters : 0.28;
  const peak = spawn.clone().add(new THREE.Vector3(0, jumpPeak, 0));
  const revealClip = petClips.get(`${state.species}_box_emerge`) || petClips.get('box_emerge') || null;
  const revealRun = revealClip ? {
    token: ++contactSerial,
    id: `adoption:${state.species}:${contactSerial}`,
    action: 'box_emerge',
    normalizedAction: 'box_emerge',
    spec: {},
    clip: revealClip,
    prop: null,
    tweenTag: 'adoption',
    cancelled: false,
    metrics: { clip: revealClip.name, scenario: 'adoption_reveal' },
  } : null;
  if (revealRun) activeContact = revealRun;
  petLayer.position.copy(start);
  const playback = revealRun ? playPetAction(revealRun) : Promise.resolve(false);
  await movePetTo(peak, 480, 'adoption');
  if (token !== adoptionVisualToken || protocol.getState().mode !== 'adoption' || revealRun?.cancelled) return;
  await movePetTo(landing, 880, 'adoption');
  if (token !== adoptionVisualToken || protocol.getState().mode !== 'adoption' || revealRun?.cancelled) return;
  await playback;
  if (revealRun && activeContact === revealRun) finishActiveContact(revealRun);
  facePetToCamera();
  diagnostic('ADOPTION_REVEAL_COMPLETE', {
    species: state.species,
    color: state.color,
    clip: revealClip?.name || null,
  });
}

function updateOwnedVisibility() {
  if (!roomRoot) return;
  const state = protocol.getState();
  const available = new Set([...state.owned, ...state.purchased]);
  roomRoot.traverse((node) => {
    if (node.userData?.optionalFixtureId) {
      const id = node.userData.optionalFixtureId;
      node.visible = available.has(id) || available.has(node.name);
      return;
    }
    // Цели могут стоять в любой комнате (сад — на кухне по канону).
    const match = /^PROP__[a-z]+__goal_(.+)$/.exec(node.name);
    if (!match) return;
    const id = match[1];
    node.visible = available.has(id) || available.has(`goal_${id}`) || available.has(node.name);
  });
}

function updateLampVisual() {
  roomLighting?.update(protocol.getState());
}

async function loadOptionalRoomAssets(room, root) {
  const specs = Array.isArray(room?.optionalFixtures) ? room.optionalFixtures : [];
  if (!specs.length) return;
  const loaded = await Promise.all(specs.map(async (spec) => {
    if (!/^[a-z0-9_.-]+\.glb$/i.test(spec.file)) throw new Error(`Unsafe optional fixture ${spec.file}`);
    const gltf = await loader.loadAsync(sameOriginUrl(`../props/${spec.file}`, descriptorUrl).href);
    return { spec, scene: gltf.scene };
  }));
  if (root !== roomRoot) {
    loaded.forEach(({ scene }) => disposeObject(scene));
    return;
  }
  for (const { spec, scene: fixture } of loaded) {
    fixture.name = spec.node;
    fixture.userData.optionalFixtureId = spec.id;
    applyJobPropPlacement(fixture, spec.placement);
    if (spec.placement?.snapToSurface) {
      root.updateMatrixWorld(true);
      const raycaster = new THREE.Raycaster(
        new THREE.Vector3(fixture.position.x, 1.45, fixture.position.z),
        new THREE.Vector3(0, -1, 0), 0, 1.5,
      );
      const support = raycaster.intersectObject(root, true)
        .find((hit) => hit.point.y >= -0.02 && hit.point.y <= 1.3);
      if (support) fixture.position.y = support.point.y;
      fixture.userData.supportHeight = fixture.position.y;
    }
    root.add(fixture);
    configureTextureAnisotropy(fixture);
  }
  root.updateMatrixWorld(true);
}

function ownsOptionalFixture(action, state = protocol.getState()) {
  if (action !== 'stars' && action !== 'nightlight') return true;
  return state.owned.includes(action) || state.purchased.includes(action);
}

function makeHitMaterial() {
  return new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false, colorWrite: false });
}

function addCollider(shape, center, metadata) {
  let geometry;
  if (shape?.toLowerCase?.() === 'sphere') {
    const radius = Number.isFinite(metadata.radius) ? metadata.radius : 0.45;
    geometry = new THREE.SphereGeometry(radius, 8, 6);
  } else {
    const size = vec3(metadata.size, [0.7, 0.7, 0.7]);
    geometry = new THREE.BoxGeometry(Math.max(size.x, 0.05), Math.max(size.y, 0.05), Math.max(size.z, 0.05));
  }
  const mesh = new THREE.Mesh(geometry, makeHitMaterial());
  mesh.position.copy(center);
  mesh.userData.interaction = metadata.interaction;
  mesh.renderOrder = -1;
  interactionLayer.add(mesh);
  interactionMeshes.push(mesh);
}

function colliderSpec(item, fallbackSize = [0.7, 0.7, 0.7]) {
  const nested = item?.hitShape && typeof item.hitShape === 'object' ? item.hitShape : null;
  return {
    shape: typeof item?.hitShape === 'string' ? item.hitShape : nested?.type || 'aabb',
    center: item?.center || nested?.center || null,
    size: item?.size || nested?.size || fallbackSize,
    radius: item?.radius ?? nested?.radius,
  };
}

function actionDescriptor(actionId, room = roomDefinition()) {
  return roomActions(room).find((entry) => entry.id === actionId) || null;
}

function doorDescriptor(targetRoom, room = roomDefinition()) {
  return roomDoors(room).find((entry) => entry.toRoom === targetRoom || entry.id === `door_${targetRoom}` || entry.id === targetRoom) || null;
}

function clearGuidance() {
  clearGroup(guidanceLayer);
}

function guidanceTarget(action) {
  const room = roomDefinition();
  if (!room || !roomRoot) return null;
  const actionId = normalizeActionId(action);
  const spec = actionDescriptor(actionId, room);
  const interactive = roomInteractives(room).find((entry) => bridgeAction(entry.id) === action || entry.id === actionId);
  const nodeName = spec?.targetNode || interactive?.targetNode || interactive?.hitNode || interactive?.node;
  const node = nodeName ? findNode(roomRoot, nodeName) : null;
  const specHit = colliderSpec(spec || {});
  const point = node
    ? node.getWorldPosition(new THREE.Vector3())
    : specHit.center
      ? vec3(specHit.center)
    : interactive?.center
      ? vec3(interactive.center)
      : null;
  return point ? { point, nodeName: node?.name || nodeName || actionId } : null;
}

function showGuidanceTarget(action) {
  clearGuidance();
  const state = protocol.getState();
  const targetRoom = PREFERRED_ROOM[action] || state.room;
  if (isRuntimePaused() || contextLost || state.mode !== 'home' || state.room !== targetRoom || currentRoomId !== state.room) {
    return { ok: false, reason: 'not_ready' };
  }
  const target = guidanceTarget(action);
  if (!target) return { ok: false, reason: 'missing_anchor' };

  const ringMaterial = new THREE.MeshBasicMaterial({
    color: 0xffa62b,
    transparent: true,
    opacity: 0.95,
    depthTest: false,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
  const ring = new THREE.Mesh(new THREE.RingGeometry(0.32, 0.43, 40), ringMaterial);
  ring.position.copy(target.point);
  ring.lookAt(camera.position);
  ring.renderOrder = 1000;
  guidanceLayer.add(ring);

  const arrow = new THREE.Mesh(
    new THREE.ConeGeometry(0.15, 0.34, 18),
    ringMaterial.clone(),
  );
  arrow.position.copy(target.point).add(new THREE.Vector3(0, 0.62, 0));
  arrow.rotation.z = Math.PI;
  arrow.renderOrder = 1000;
  guidanceLayer.add(arrow);
  if (renderer) renderer.render(scene, camera);
  diagnostic('GUIDANCE_TARGET_SHOWN', { action, room: state.room, target: target.nodeName });
  return { ok: true, action, room: state.room };
}

function cancelNavigation() {
  const hadNavigation = navigation !== null;
  navigationSerial += 1;
  navigation = null;
  clearGuidance();
  if (!roomCurtainActionId || protocol.getPending()?.id !== roomCurtainActionId || isRuntimePaused() || contextLost) {
    clearRoomCurtain();
  }
  if (activeTween?.tag === 'navigation') {
    const interrupted = activeTween;
    activeTween = null;
    interrupted.locomotion?.action?.stop();
    petMixer?.update(0);
    petGrowth?.update(0);
    interrupted.resolve();
  }
  if (hadNavigation && petModel) {
    petLayer.position.copy(petHome);
    facePetToCamera();
    petLayer.updateMatrixWorld(true);
  }
}

function roomRoute(fromRoom, targetRoom) {
  if (fromRoom === targetRoom) return [];
  if (fromRoom === 'living' || targetRoom === 'living') return [targetRoom];
  return ['living', targetRoom];
}

async function advanceNavigation(token) {
  const route = navigation;
  if (!route || route.token !== token) return { ok: false, reason: 'cancelled' };
  const state = protocol.getState();
  if (isRuntimePaused() || contextLost || state.mode !== 'home' || anyMinigameActive()) {
    cancelNavigation();
    return { ok: false, reason: 'not_ready' };
  }
  if (state.room === route.targetRoom) {
    navigation = null;
    await roomReadyPromise;
    return route.guidanceAction
      ? showGuidanceTarget(route.guidanceAction)
      : { ok: true, room: state.room };
  }
  if (protocol.getPending()) return { ok: true, reason: 'waiting_for_pending' };

  const nextRoom = roomRoute(state.room, route.targetRoom)[0];
  const transition = `${state.room}:${nextRoom}`;
  if (!nextRoom || route.steps >= 4 || route.visited.has(transition) || !doorDescriptor(nextRoom)) {
    cancelNavigation();
    diagnostic('ROOM_ROUTE_ABORTED', { room: state.room, targetRoom: route.targetRoom });
    return { ok: false, reason: 'route_unavailable' };
  }
  route.steps += 1;
  route.visited.add(transition);
  const result = await beginAction(
    'room',
    nextRoom,
    route.guidanceAction ? 'guidance_route' : 'flutter_hud_route',
    () => navigation === route && !isRuntimePaused(),
  );
  if (navigation !== route) {
    if (navigation && !protocol.getPending()) void advanceNavigation(navigation.token);
    return { ok: false, reason: 'cancelled' };
  }
  if (!result.ok) {
    diagnostic('ROOM_ROUTE_STEP_REJECTED', {
      room: state.room,
      targetRoom: route.targetRoom,
      nextRoom,
      reason: result.reason || 'unknown',
    });
    cancelNavigation();
    return result;
  }
  route.inFlightId = result.id;
  return result;
}

function startNavigation(targetRoom, guidanceAction = null) {
  const state = protocol.getState();
  if (!descriptor?.rooms?.[targetRoom]) return { ok: false, reason: 'unknown_room' };
  if (isRuntimePaused() || contextLost || !readySent || state.mode !== 'home' || anyMinigameActive()) {
    return { ok: false, reason: 'not_ready' };
  }
  if (navigation?.targetRoom === targetRoom && navigation.guidanceAction === guidanceAction) {
    return { ok: true, targetRoom, route: roomRoute(state.room, targetRoom), alreadyNavigating: true };
  }
  cancelNavigation();
  const route = {
    token: ++navigationSerial,
    targetRoom,
    guidanceAction,
    steps: 0,
    visited: new Set(),
    inFlightId: null,
  };
  navigation = route;
  void advanceNavigation(route.token);
  return { ok: true, targetRoom, route: roomRoute(state.room, targetRoom) };
}

function showAction(action) {
  if (!GUIDANCE_ACTIONS.has(action)) return { ok: false, reason: 'unknown_action' };
  const targetRoom = PREFERRED_ROOM[action];
  return targetRoom ? startNavigation(targetRoom, action) : showGuidanceTarget(action);
}

function interactionPointFor(action, type, targetRoom) {
  const room = roomDefinition();
  if (!room || !roomRoot) return petLayer.position.clone();
  if (action === 'room') {
    const door = doorDescriptor(targetRoom, room);
    const key = type === 'target' ? door?.targetNode : door?.approachNode;
    return nodeWorldPosition(roomRoot, key || door?.hitNode, petLayer.position.toArray());
  }
  if (action === 'lamp') {
    const interactive = roomInteractives(room).find((entry) => bridgeAction(entry.id) === 'lamp');
    const lamp = findNode(roomRoot, interactive?.node);
    if (lamp) {
      const bounds = new THREE.Box3().setFromObject(lamp);
      return new THREE.Vector3(bounds.max.x + 0.38, room.floor?.height ?? 0, bounds.max.z + 0.3);
    }
  }
  const id = normalizeActionId(action);
  const spec = actionDescriptor(id, room);
  if (type === 'watch' && spec?.watch) {
    const watch = Array.isArray(spec.watch)
      ? spec.watch : camera.aspect > 1 ? spec.watch.landscape : spec.watch.portrait;
    if (watch) return vec3(watch, petLayer.position.toArray());
  }
  if (type === 'approach' && spec?.approach) return vec3(spec.approach, petLayer.position.toArray());
  if (type === 'target' && spec?.target) return vec3(spec.target, petLayer.position.toArray());
  const key = type === 'target' ? spec?.targetNode : spec?.approachNode;
  if (key) return nodeWorldPosition(roomRoot, key, petLayer.position.toArray());
  const interactive = roomInteractives(room).find((entry) => bridgeAction(entry.id) === action || entry.id === id);
  if (interactive?.center) return vec3(interactive.center, petLayer.position.toArray());
  return nodeWorldPosition(roomRoot, interactive?.node, petLayer.position.toArray());
}

function positionJobPetObserver(animated = true) {
  const state = jobRound?.getState();
  if (!state || !['J02', 'J04'].includes(state.jobId) || state.stage === 'idle' || !petModel) return;
  const action = `job_${state.jobId.toLowerCase()}`;
  const target = interactionPointFor(action, 'watch');
  const focus = interactionPointFor(action, 'target');
  if (animated) {
    void movePetTo(target, 460).then(() => faceMovement(petLayer.position, focus));
  } else {
    target.y = standingHeight(target);
    petLayer.position.copy(target);
    faceMovement(petLayer.position, focus);
  }
}

function doorPreviewPoint(doorApproach) {
  const direction = doorApproach.clone().sub(petLayer.position).setY(0);
  const distance = direction.length();
  if (distance <= DOOR_APPROACH_METERS) return doorApproach;
  return petLayer.position.clone().addScaledVector(direction, DOOR_APPROACH_METERS / distance);
}

function buildInteractions(room) {
  clearGroup(interactionLayer);
  interactionMeshes.length = 0;
  const mappedActions = new Set();
  for (const item of roomInteractives(room)) {
    const action = bridgeAction(item.id);
    if (!action) continue;
    if (PREFERRED_ROOM[action] && PREFERRED_ROOM[action] !== room.id) continue;
    const hit = colliderSpec(item);
    const lamp = action === 'lamp' ? findNode(roomRoot, item.node) : null;
    const lampBounds = lamp ? new THREE.Box3().setFromObject(lamp) : null;
    const center = lampBounds && !lampBounds.isEmpty()
      ? lampBounds.getCenter(new THREE.Vector3())
      : hit.center ? vec3(hit.center) : nodeWorldPosition(roomRoot, item.hitNode || item.node);
    addCollider(hit.shape, center, {
      size: lampBounds && !lampBounds.isEmpty()
        ? lampBounds.getSize(new THREE.Vector3()).addScalar(0.12).toArray() : hit.size,
      radius: hit.radius,
      interaction: { action, actionId: item.id, source: 'raycast' },
    });
    mappedActions.add(action);
  }
  for (const item of roomActions(room)) {
    const action = bridgeAction(item.id);
    if (!action || mappedActions.has(action)) continue;
    if (PREFERRED_ROOM[action] && PREFERRED_ROOM[action] !== room.id) continue;
    if (!ownsOptionalFixture(action)) continue;
    const hit = colliderSpec(item, [0.72, 0.62, 0.72]);
    const actionProp = actionDescriptor(item.id, room)?.propNode;
    const prop = actionProp ? findNode(roomRoot, actionProp) : null;
    const propBounds = prop ? new THREE.Box3().setFromObject(prop) : null;
    const center = propBounds && !propBounds.isEmpty()
      ? propBounds.getCenter(new THREE.Vector3())
      : hit.center ? vec3(hit.center) : nodeWorldPosition(roomRoot, item.targetNode || item.approachNode);
    addCollider(hit.shape, center, {
      size: propBounds && !propBounds.isEmpty()
        ? propBounds.getSize(new THREE.Vector3()).addScalar(0.08).toArray() : hit.size,
      radius: hit.radius,
      interaction: { action, actionId: item.id, source: 'raycast' },
    });
    mappedActions.add(action);
  }
  for (const door of roomDoors(room)) {
    const hit = colliderSpec(door, [0.8, 1.7, 0.28]);
    const center = hit.center ? vec3(hit.center) : nodeWorldPosition(roomRoot, door.hitNode);
    addCollider(hit.shape, center, {
      size: hit.size,
      radius: hit.radius,
      interaction: { action: 'room', targetRoom: door.toRoom, source: 'raycast' },
    });
  }
  const available = new Set([...protocol.getState().owned, ...protocol.getState().purchased]);
  for (const scenario of room.petScenarios || []) {
    if (scenario.requiredOwned && !available.has(scenario.requiredOwned)) continue;
    const prop = findNode(roomRoot, scenario.propNode);
    if (!prop?.visible) continue;
    const bounds = new THREE.Box3().setFromObject(prop);
    if (bounds.isEmpty()) continue;
    addCollider('aabb', bounds.getCenter(new THREE.Vector3()), {
      size: bounds.getSize(new THREE.Vector3()).addScalar(0.12).toArray(),
      interaction: { scenario: scenario.id },
    });
  }
  if (room.id === 'kitchen' && !mappedActions.has('wash_dishes')) {
    addCollider('aabb', new THREE.Vector3(-0.15, 0.75, -2.1), {
      size: [1.05, 1.1, 0.9],
      interaction: { action: 'wash_dishes', source: 'raycast' },
    });
  }
}

function applyAdoptionPlacement(root, placement = {}) {
  root.position.copy(vec3(placement.position, [0, 0, 0]));
  const rotation = placement.rotationDegrees || placement.rotation || [0, 0, 0];
  const degrees = Boolean(placement.rotationDegrees);
  const euler = Array.isArray(rotation) ? rotation : [rotation.x || 0, rotation.y || 0, rotation.z || 0];
  root.rotation.set(...euler.slice(0, 3).map((value) => degrees ? THREE.MathUtils.degToRad(value) : value));
  if (Number.isFinite(placement.scale)) root.scale.setScalar(placement.scale);
  else root.scale.copy(vec3(placement.scale, [1, 1, 1]));
  root.updateMatrixWorld(true);
}

async function loadAdoptionAsset(room) {
  const adoption = room?.adoption;
  if (!adoption?.asset) return;
  const asset = descriptor?.assets?.[adoption.asset] || {};
  const assetFile = asset.file || adoption.asset;
  if (!/^[a-z0-9_.-]+$/i.test(assetFile)) throw new Error('Unsafe adoption asset file');
  if (adoptionRoot && adoptionAssetKey === adoption.asset) return;
  if (!adoptionRoot && adoptionAssetKey === adoption.asset) return adoptionReadyPromise;
  if (protocol.getState().mode === 'adoption') setStatus('Открываем коробку…');
  const assetKey = adoption.asset;
  adoptionAssetKey = assetKey;
  const url = sameOriginUrl(assetFile, descriptorUrl);
  let gltf;
  try {
    gltf = await loader.loadAsync(url.href);
  } catch (error) {
    if (adoptionAssetKey === assetKey) adoptionAssetKey = null;
    throw error;
  }
  if (assetKey !== descriptor?.rooms?.living?.adoption?.asset) {
    disposeObject(gltf.scene);
    if (adoptionAssetKey === assetKey) adoptionAssetKey = null;
    return;
  }
  clearGroup(adoptionLayer);
  adoptionRoot = gltf.scene;
  adoptionRoot.name = adoption.rootNode || asset.rootNode || 'PROP__living__adoption_box';
  applyAdoptionPlacement(adoptionRoot, adoption.placement);
  adoptionLayer.add(adoptionRoot);
  configureTextureAnisotropy(adoptionRoot);
  await updateAdoptionVisual(false);
  if (renderer) renderer.render(scene, camera);
}

function applyRoomStaging(room, root) {
  for (const transform of room.runtimeStaging?.nodeTransforms || []) {
    const object = findNode(root, transform.node);
    if (!object) continue;
    object.position.add(vec3(transform.offset, [0, 0, 0]));
    if (Number.isFinite(transform.scale)) object.scale.multiplyScalar(transform.scale);
    else if (Array.isArray(transform.scale) && transform.scale.length >= 3) {
      object.scale.multiply(vec3(transform.scale, [1, 1, 1]));
    }
    object.updateMatrixWorld(true);
  }
  for (const transform of room.runtimeStaging?.materialTransforms || []) {
    root.traverse((object) => {
      const materials = Array.isArray(object.material) ? object.material : [object.material];
      if (!materials.some((material) => material?.name === transform.material)) return;
      object.position.add(vec3(transform.offset, [0, 0, 0]));
      if (Number.isFinite(transform.scale)) object.scale.multiplyScalar(transform.scale);
      else if (Array.isArray(transform.scale) && transform.scale.length >= 3) {
        object.scale.multiply(vec3(transform.scale, [1, 1, 1]));
      }
      object.updateMatrixWorld(true);
    });
  }
  for (const style of room.runtimeStaging?.materialStyles || []) {
    root.traverse((object) => {
      if (!object.isMesh || object.material?.name !== style.material) return;
      if (typeof style.visible === 'boolean') object.visible = style.visible;
      const material = object.material;
      if (style.clearMaps) {
        material.map = null;
        material.normalMap = null;
        material.metalnessMap = null;
        material.roughnessMap = null;
        material.aoMap = null;
      }
      if (style.color) material.color.set(style.color);
      if (Number.isFinite(style.roughness)) material.roughness = style.roughness;
      if (Number.isFinite(style.metalness)) material.metalness = style.metalness;
      material.needsUpdate = true;
    });
  }
  for (const spec of room.runtimeStaging?.meshCopies || []) {
    const matches = [];
    root.traverse((object) => {
      if (object.isMesh && object.material?.name === spec.material &&
          (!spec.sourceNode || object.name === spec.sourceNode)) matches.push(object);
    });
    if (matches.length !== 1) {
      console.warn(`Room copy ${spec.node}: expected one ${spec.material} mesh, found ${matches.length}`);
      continue;
    }
    const source = matches[0];
    const copy = source.clone(false);
    copy.name = spec.node;
    if (Number.isFinite(spec.yawDegrees) && spec.yawDegrees !== 0) {
      source.geometry.computeBoundingBox();
      const center = source.geometry.boundingBox.getCenter(new THREE.Vector3())
        .multiply(source.scale).applyQuaternion(source.quaternion).add(source.position);
      const pivot = new THREE.Group();
      pivot.name = `${spec.node}__pivot`;
      pivot.position.copy(center).add(vec3(spec.offset, [0, 0, 0]));
      pivot.rotation.y = THREE.MathUtils.degToRad(spec.yawDegrees);
      copy.position.sub(center);
      pivot.add(copy);
      source.parent.add(pivot);
    } else {
      copy.position.add(vec3(spec.offset, [0, 0, 0]));
      source.parent.add(copy);
    }
  }
}

function applyJobPropPlacement(root, placement = {}) {
  root.position.copy(vec3(placement.position, [0, 0, 0]));
  const rotation = placement.rotationDegrees || [0, 0, 0];
  root.rotation.set(...rotation.map((value) => THREE.MathUtils.degToRad(value)));
  if (Number.isFinite(placement.scale)) root.scale.setScalar(placement.scale);
  else root.scale.copy(vec3(placement.scale, [1, 1, 1]));
  root.visible = placement.visible !== false;
  root.userData.jobInitial = {
    position: root.position.clone(),
    rotation: root.rotation.clone(),
    scale: root.scale.clone(),
    visible: root.visible,
  };
  root.updateMatrixWorld(true);
}

async function installJobClothFolds(payload, stillCurrent) {
  const pending = [];
  try {
    for (const id of ['unfolded_towel_1', 'unfolded_towel_2']) {
      const root = jobProps.get(id);
      if (!root) throw new Error(`Missing J03 cloth source ${id}`);
      const meshes = [];
      root.traverse((object) => {
        if (object.isMesh && object.geometry?.attributes?.position) meshes.push(object);
      });
      if (meshes.length !== 1) throw new Error(`J03 cloth ${id} needs exactly one mesh`);
      const mesh = meshes[0];
      mesh.geometry.computeBoundingBox();
      const sourceBounds = mesh.geometry.boundingBox.clone();
      const sourceGeometryUuid = mesh.geometry.uuid;
      const controller = await createAttempt8ClothFold({
        THREE, mesh, config: payload.config, sidecar: payload.sidecar,
        sourceGlbBytes: payload.sourceGlbBytes,
      });
      pending.push({ id, root, mesh, controller, sourceBounds, sourceGeometryUuid });
      if (!stillCurrent()) {
        pending.forEach((entry) => entry.controller.dispose());
        return false;
      }
    }
    pending.forEach((entry) => jobClothFolds.set(entry.id, entry));
    return true;
  } catch (error) {
    pending.forEach((entry) => entry.controller.dispose());
    throw error;
  }
}

function disposeJobClothFolds() {
  activeJobClothFold = null;
  for (const entry of jobClothFolds.values()) entry.controller.dispose();
  jobClothFolds.clear();
}

function resetJobClothFolds() {
  for (const entry of jobClothFolds.values()) entry.controller.reset();
}

function cancelActiveJobClothFold(reset = true) {
  if (!activeJobClothFold) return;
  if (reset) activeJobClothFold.entry.controller.reset();
  activeJobClothFold = null;
  if (renderer) renderer.render(scene, camera);
}

function setJobClothFoldProgress(entry, progress) {
  if (!entry) return false;
  const total = THREE.MathUtils.clamp(progress, 0, 1);
  if (total <= 0.5) entry.controller.setProgresses([total * 2, 0]);
  else entry.controller.setProgresses([1, (total - 0.5) * 2]);
  if (renderer) renderer.render(scene, camera);
  return true;
}

function jobClothFoldDiagnostics() {
  return [...jobClothFolds.values()].map((entry) => {
    const diagnostics = entry.controller.diagnostics();
    const progresses = diagnostics.progresses.map((value) => Number(value.toFixed(4)));
    const activeStep = progresses[0] < 1 ? 0 : 1;
    return {
      id: entry.id,
      progresses,
      activeStep,
      progress: progresses[activeStep],
      estimatedPlyThickness: diagnostics.estimatedPlyThickness,
      sourceVisible: entry.root.visible && entry.controller.mesh.visible,
      identity: {
        rootUuid: entry.root.uuid,
        meshUuid: entry.mesh.uuid,
        sourceGeometryUuid: entry.sourceGeometryUuid,
        liveGeometryUuid: entry.controller.geometry.uuid,
      },
    };
  });
}

function jobClothFoldScreenEdges(entry) {
  if (!entry) return { source: null, valid: null };
  entry.mesh.updateWorldMatrix(true, false);
  const { min, max } = entry.sourceBounds;
  const projected = [
    [min.x, min.y, min.z], [min.x, min.y, max.z], [min.x, max.y, min.z], [min.x, max.y, max.z],
    [max.x, min.y, min.z], [max.x, min.y, max.z], [max.x, max.y, min.z], [max.x, max.y, max.z],
  ].map((point) => cssPointForWorld(new THREE.Vector3(...point).applyMatrix4(entry.mesh.matrixWorld))).filter(Boolean);
  if (!projected.length) return { source: null, valid: null };
  const minX = Math.min(...projected.map((point) => point.x));
  const maxX = Math.max(...projected.map((point) => point.x));
  const minY = Math.min(...projected.map((point) => point.y));
  const maxY = Math.max(...projected.map((point) => point.y));
  if (maxX - minX >= maxY - minY) {
    const y = (minY + maxY) * 0.5;
    return { source: { x: maxX, y }, valid: { x: minX, y } };
  }
  const x = (minX + maxX) * 0.5;
  return { source: { x, y: maxY }, valid: { x, y: minY } };
}

function jobClothFoldTotalProgress(entry) {
  const [first, second] = entry?.controller.diagnostics().progresses || [0, 0];
  return second > 0 ? 0.5 + second * 0.5 : first * 0.5;
}

function jobClothFoldDragPoints(entry) {
  const edges = jobClothFoldScreenEdges(entry);
  if (!edges.source || !edges.valid) return edges;
  const progress = jobClothFoldTotalProgress(entry);
  return {
    source: {
      x: THREE.MathUtils.lerp(edges.source.x, edges.valid.x, progress),
      y: THREE.MathUtils.lerp(edges.source.y, edges.valid.y, progress),
    },
    valid: edges.valid,
    fullSource: edges.source,
    progress,
  };
}

function resetJobPropVisuals() {
  cancelActiveJobClothFold();
  resetJobClothFolds();
  const jobBall = roomRoot?.getObjectByName('PROP__living__ball');
  if (jobBall?.userData.jobInitialScale) {
    jobBall.scale.copy(jobBall.userData.jobInitialScale);
    delete jobBall.userData.jobInitialScale;
  }
  for (const root of jobProps.values()) {
    jobPropAnimationTokens.set(root, (jobPropAnimationTokens.get(root) || 0) + 1);
    const initial = root.userData.jobInitial;
    if (!initial) continue;
    root.position.copy(initial.position);
    root.rotation.copy(initial.rotation);
    root.scale.copy(initial.scale);
    root.visible = initial.visible;
  }
  if (renderer) renderer.render(scene, camera);
}

function configureTextureAnisotropy(root) {
  const profile = qualityController.getState().profile;
  applyTextureResolution(root, profile);
  applyTextureFiltering(root, renderer, profile);
}

async function syncKitchenFridgeQuality() {
  const root = currentRoomId === 'kitchen' ? roomRoot : null;
  if (!root) return;
  const original = findNode(root, 'ROOM__kitchen__static__mesh_10');
  if (!original?.isMesh || original.material?.name !== 'Material_0.048') {
    console.warn('Kitchen fridge mesh contract changed');
    return;
  }
  const replacement = findNode(root, 'ROOM__kitchen__service_fridge');
  if (qualityController.getState().tier !== 'high') {
    ++kitchenFridgeLoadSerial;
    kitchenFridgePending = null;
    original.visible = true;
    if (replacement) {
      root.remove(replacement);
      disposeObject(replacement);
    }
    return;
  }
  if (replacement) {
    original.visible = false;
    return;
  }
  if (kitchenFridgePending?.root === root) return kitchenFridgePending.promise;
  const serial = ++kitchenFridgeLoadSerial;
  const roomToken = roomLoadToken;
  const promise = (async () => {
    let gltf;
    try {
      gltf = await loader.loadAsync(sameOriginUrl('./props/fridge_quality.glb', location.href).href);
    } catch (error) {
      if (serial === kitchenFridgeLoadSerial && roomRoot === root) {
        console.warn('Kitchen fridge quality asset unavailable', error);
      }
      return;
    }
    if (serial !== kitchenFridgeLoadSerial || roomToken !== roomLoadToken || roomRoot !== root ||
        qualityController.getState().tier !== 'high') {
      disposeObject(gltf.scene);
      return;
    }
    const meshes = [];
    gltf.scene.traverse((object) => { if (object.isMesh) meshes.push(object); });
    if (meshes.length !== 1) {
      disposeObject(gltf.scene);
      console.warn('Kitchen fridge source mesh contract changed');
      return;
    }
    gltf.scene.name = 'ROOM__kitchen__service_fridge';
    gltf.scene.position.set(-1.9232873030069484, 0.6648572179076735, -2.222676002057975);
    gltf.scene.scale.setScalar(0.7446457315027606);
    configureTextureAnisotropy(gltf.scene);
    root.add(gltf.scene);
    original.visible = false;
  })();
  kitchenFridgePending = { root, promise };
  try { await promise; } finally {
    if (kitchenFridgePending?.promise === promise) kitchenFridgePending = null;
  }
}

const livingWallpaperMeshes = new Set([
  'ROOM__living__static__mesh_1',
  'ENVELOPE__living__left_front', 'ENVELOPE__living__left_rear',
  'ENVELOPE__living__left_lintel', 'ENVELOPE__living__right_front',
  'ENVELOPE__living__right_rear', 'ENVELOPE__living__right_lintel',
]);

const roomFloorFinishes = Object.freeze({
  living: { material: 'APT | floor_wood', file: 'oak-floor.png' },
  kitchen: { material: 'APT | floor_wood', file: 'oak-floor.png' },
  bathroom: { material: 'APT | tile', file: 'ceramic-floor.png' },
});

async function installWindowGarden(root, roomId, token) {
  if (roomId !== 'living' && roomId !== 'kitchen') return;
  let texture;
  try {
    texture = await new THREE.TextureLoader().loadAsync(
      sameOriginUrl('./rooms/window-garden.webp', location.href).href,
    );
  } catch (error) {
    console.warn(`Window garden unavailable: ${roomId}`, error);
    return;
  }
  if (token !== roomLoadToken || roomRoot !== root) {
    texture.dispose();
    return;
  }
  const windowMaterials = new Set(['APT | pale daylight', 'FIX | sky_lit']);
  const targets = [];
  root.traverse((object) => {
    if (!object.isMesh) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    for (const material of materials) {
      if (windowMaterials.has(material?.name)) targets.push(material);
    }
  });
  if (targets.length !== 2) {
    texture.dispose();
    console.warn(`Window surface contract changed: ${roomId}`);
    return;
  }
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.flipY = false;
  texture.needsUpdate = true;
  for (const material of targets) {
    material.map = texture;
    material.color.set('#ffffff');
    material.emissive?.set('#202020');
    material.needsUpdate = true;
  }
  configureTextureAnisotropy(root);
}

async function installBathroomBathtubQuality(root, token) {
  let gltf;
  try {
    gltf = await loader.loadAsync(
      sameOriginUrl('./props/bathtub_quality.glb', location.href).href,
    );
  } catch (error) {
    console.warn('Bathroom bathtub quality asset unavailable', error);
    return;
  }
  if (token !== roomLoadToken || roomRoot !== root) {
    disposeObject(gltf.scene);
    return;
  }
  const bathtub = findNode(root, 'PROP__bathroom__bathtub');
  const meshes = [];
  gltf.scene.traverse((object) => { if (object.isMesh) meshes.push(object); });
  if (!bathtub?.isMesh || bathtub.material?.name !== 'Material_0.017' || meshes.length !== 1) {
    disposeObject(gltf.scene);
    console.warn('Bathroom bathtub mesh contract changed');
    return;
  }
  const replacement = meshes[0];
  bathtub.geometry.dispose();
  disposeMaterial(bathtub.material);
  bathtub.geometry = replacement.geometry;
  bathtub.material = replacement.material;
  bathtub.material.name = 'Material_0.017';
}

async function installRoomFloorFinish(root, roomId, token) {
  const finish = roomFloorFinishes[roomId];
  if (!finish) return;
  let texture;
  try {
    texture = await new THREE.TextureLoader().loadAsync(
      sameOriginUrl(`./rooms/${finish.file}`, location.href).href,
    );
  } catch (error) {
    console.warn(`Room floor finish unavailable: ${roomId}`, error);
    return;
  }
  if (token !== roomLoadToken || roomRoot !== root) {
    texture.dispose();
    return;
  }
  const targets = [];
  root.traverse((object) => {
    if (object.isMesh && object.material?.name === finish.material) targets.push(object);
  });
  if (targets.length !== 1 || targets[0].material.map) {
    texture.dispose();
    console.warn(`Room floor mesh contract changed: ${roomId}`);
    return;
  }
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.flipY = false;
  if (roomId === 'bathroom') {
    texture.wrapS = THREE.RepeatWrapping;
    texture.wrapT = THREE.RepeatWrapping;
    texture.repeat.set(3, 3);
  }
  texture.needsUpdate = true;
  targets[0].material.map = texture;
  targets[0].material.color.set('#ffffff');
  targets[0].material.needsUpdate = true;
  configureTextureAnisotropy(root);
}

async function installLivingWallpaper(root, token) {
  let texture;
  try {
    texture = await new THREE.TextureLoader().loadAsync(
      sameOriginUrl('./rooms/living-wallpaper.png', location.href).href,
    );
  } catch (error) {
    console.warn('Living wallpaper unavailable', error);
    return;
  }
  if (token !== roomLoadToken || roomRoot !== root) {
    texture.dispose();
    return;
  }
  const targets = [];
  root.traverse((object) => {
    if (object.isMesh && livingWallpaperMeshes.has(object.name)) targets.push(object);
  });
  if (targets.length !== livingWallpaperMeshes.size ||
      targets.some((object) => object.material?.name !== 'APT | plaster')) {
    texture.dispose();
    console.warn('Living wallpaper mesh contract changed');
    return;
  }
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.flipY = false;
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(3, 3);
  texture.needsUpdate = true;
  for (const object of targets) {
    object.material.map = texture;
    object.material.needsUpdate = true;
  }
  configureTextureAnisotropy(root);
}

function applyCurrentGraphicsQuality() {
  const state = qualityController.getState();
  if (!renderer) return state;
  applyRendererQuality(renderer, state.profile, {
    devicePixelRatio: window.devicePixelRatio,
    width: Math.max(1, canvas.clientWidth || innerWidth),
    height: Math.max(1, canvas.clientHeight || innerHeight),
  });
  applyTextureFiltering(scene, renderer, state.profile);
  applyTextureResolution(scene, state.profile);
  void syncKitchenFridgeQuality();
  return state;
}

function setGraphicsQuality(mode) {
  if (mode === qualityController.getState().mode) return { ok: true, ...qualityController.getState() };
  try {
    const state = qualityController.setMode(mode);
    applyCurrentGraphicsQuality();
    return { ok: true, ...state };
  } catch {
    return { ok: false, reason: 'invalid_quality_mode', ...qualityController.getState() };
  }
}

function graphicsQualityDiagnostics() {
  const originalFridge = currentRoomId === 'kitchen' ? findNode(roomRoot, 'ROOM__kitchen__static__mesh_10') : null;
  const serviceFridges = currentRoomId === 'kitchen'
    ? roomRoot?.children.filter((child) => child.name === 'ROOM__kitchen__service_fridge') || [] : [];
  return { ...qualityController.getState(), dpr: renderer?.getPixelRatio?.() ?? null,
    textures: textureResolutionDiagnostics(scene),
    fridge: { originalVisible: originalFridge?.visible ?? null, serviceCount: serviceFridges.length } };
}

async function loadJobProps(room, jobId = currentJobId()) {
  const token = ++jobPropLoadToken;
  disposeJobClothFolds();
  clearGroup(jobPropLayer);
  jobProps.clear();
  jobPropsJobId = null;
  const specs = (room?.jobProps || []).filter((entry) => entry.jobId === jobId || entry.jobId === 'SCENE');
  if (!specs.length) return;
  let towelPayload = null;
  if (jobId === 'J03') {
    const glbUrl = sameOriginUrl('../props/towel_attempt8_416k.glb', descriptorUrl);
    const configUrl = sameOriginUrl('../props/towel_attempt8_config.json', descriptorUrl);
    const sidecarUrl = sameOriginUrl('../props/towel_attempt8_correction.bin', descriptorUrl);
    const [glbResponse, configResponse, sidecarResponse] = await Promise.all([
      fetch(glbUrl), fetch(configUrl), fetch(sidecarUrl),
    ]);
    if (![glbResponse, configResponse, sidecarResponse].every((response) => response.ok)) {
      throw new Error('J03 Attempt8 assets unavailable');
    }
    const [sourceGlbBytes, config, sidecar] = await Promise.all([
      glbResponse.arrayBuffer(), configResponse.json(), sidecarResponse.arrayBuffer(),
    ]);
    const gltf = await loader.parseAsync(sourceGlbBytes, new URL('./', glbUrl).href);
    towelPayload = { sourceGlbBytes, config, sidecar, scene: gltf.scene };
    if (token !== jobPropLoadToken || currentRoomId !== room.id) {
      disposeObject(gltf.scene);
      return;
    }
  }
  let towelCopies = 0;
  const results = await Promise.allSettled(specs.map(async (spec) => {
    if (jobId === 'J03' && /^unfolded_towel_[12]$/.test(spec.id)) {
      const source = towelCopies++ === 0 ? towelPayload.scene : towelPayload.scene.clone(true);
      const wrapper = new THREE.Group();
      wrapper.position.set(5.583198071690276e-5, 0.034505829215049744, -3.8759069866500795e-5);
      wrapper.scale.setScalar(0.5203195214271545);
      wrapper.add(source);
      const root = new THREE.Group();
      root.add(wrapper);
      return { spec, root };
    }
    if (!/^[a-z0-9_.-]+\.glb$/i.test(spec.file)) throw new Error(`Unsafe job prop file ${spec.file}`);
    const url = sameOriginUrl(`../props/${spec.file}`, descriptorUrl);
    const gltf = await loader.loadAsync(url.href);
    return { spec, root: gltf.scene };
  }));
  const loaded = results.filter((result) => result.status === 'fulfilled')
    .map((result) => result.value);
  const failed = results.find((result) => result.status === 'rejected');
  if (failed) {
    loaded.forEach(({ root }) => disposeObject(root));
    if (towelPayload && !loaded.some(({ root }) => root.getObjectById(towelPayload.scene.id))) {
      disposeObject(towelPayload.scene);
    }
    throw failed.reason;
  }
  if (token !== jobPropLoadToken || currentRoomId !== room.id) {
    loaded.forEach(({ root }) => disposeObject(root));
    return;
  }
  for (const { spec, root } of loaded) {
    root.name = `JOBPROP__${spec.id}`;
    root.userData.jobPropId = spec.id;
    applyJobPropPlacement(root, spec.placement);
    configureTextureAnisotropy(root);
    if (spec.jobId === 'SCENE' || ['J01', 'J05', 'J06'].includes(jobId)) prepareRoomShadows(root);
    jobPropLayer.add(root);
    jobProps.set(spec.id, root);
  }
  if (jobId === 'J03') {
    let installed;
    try {
      installed = await installJobClothFolds(towelPayload,
        () => token === jobPropLoadToken && currentRoomId === room.id);
    } catch (error) {
      if (token === jobPropLoadToken && currentRoomId === room.id) {
        clearGroup(jobPropLayer);
        jobProps.clear();
      }
      throw error;
    }
    if (!installed) return;
  }
  jobPropsJobId = jobId;
  diagnostic('JOB_PROPS_READY', { room: room.id, jobId, props: [...jobProps.keys()] });
  if (renderer) renderer.render(scene, camera);
}

function animateJobProp(root, target, duration = 300, arcHeight = 0, targetRotation = null) {
  if (!root || !Array.isArray(target)) return Promise.resolve(false);
  const token = (jobPropAnimationTokens.get(root) || 0) + 1;
  jobPropAnimationTokens.set(root, token);
  root.visible = true;
  const start = root.position.clone();
  const destination = vec3(target);
  const startQuaternion = root.quaternion.clone();
  const destinationQuaternion = targetRotation
    ? new THREE.Quaternion().setFromEuler(targetRotation) : null;
  const effectiveDuration = protocol.getState().reducedMotion ? 0 : duration;
  if (effectiveDuration === 0) {
    root.position.copy(destination);
    if (destinationQuaternion) root.quaternion.copy(destinationQuaternion);
    if (root === jobProps.get('dustpan')) updateJ06PanFillVisual();
    if (renderer) renderer.render(scene, camera);
    return Promise.resolve(true);
  }
  const startedAt = performance.now();
  return new Promise((resolve) => {
    const tick = (now) => {
      if (!root.parent || jobPropAnimationTokens.get(root) !== token) return resolve(false);
      const t = Math.min(1, (now - startedAt) / effectiveDuration);
      const eased = 1 - ((1 - t) ** 3);
      root.position.lerpVectors(start, destination, eased);
      if (arcHeight > 0) root.position.y += Math.sin(Math.PI * t) * arcHeight;
      if (destinationQuaternion) root.quaternion.slerpQuaternions(startQuaternion, destinationQuaternion, eased);
      if (root === jobProps.get('dustpan')) updateJ06PanFillVisual();
      if (renderer) renderNow();
      if (t < 1) requestAnimationFrame(tick);
      else resolve(true);
    };
    requestAnimationFrame(tick);
  });
}

const J06_DEBRIS_LAYOUT = Object.freeze([
  [-0.055, -0.022, 0.015, 5], [-0.028, 0.036, 0.011, 7], [0.004, -0.014, 0.018, 6],
  [0.035, 0.026, 0.012, 5], [0.061, -0.008, 0.009, 8], [-0.012, -0.052, 0.01, 6],
  [0.024, 0.058, 0.008, 5], [-0.067, 0.047, 0.008, 7], [0.073, 0.041, 0.007, 6],
]);

function makeJ06DebrisCluster(id, toneOffset = 0) {
  const group = new THREE.Group();
  group.name = `RUNTIME__${id}__debris`;
  const smudge = new THREE.Mesh(new THREE.CircleGeometry(0.082, 28), new THREE.MeshBasicMaterial({
    color: toneOffset ? 0x796a5a : 0x6d6255, transparent: true, opacity: 0.2,
    depthWrite: false, toneMapped: false, side: THREE.DoubleSide,
  }));
  smudge.rotation.x = -Math.PI / 2;
  smudge.scale.set(1.15, 0.72, 1);
  smudge.position.y = 0.001;
  smudge.renderOrder = 805;
  group.add(smudge);
  const colors = [0x51483f, 0x756555, 0x9b8062, 0x5f584f];
  for (let index = 0; index < J06_DEBRIS_LAYOUT.length; index += 1) {
    const [x, z, radius, sides] = J06_DEBRIS_LAYOUT[index];
    const piece = new THREE.Mesh(new THREE.CircleGeometry(radius, sides), new THREE.MeshStandardMaterial({
      color: colors[(index + toneOffset) % colors.length], roughness: 1, metalness: 0,
      transparent: true, opacity: 0.94, depthWrite: false, side: THREE.DoubleSide,
    }));
    piece.position.set(x, 0.004 + (index % 3) * 0.0015, z);
    piece.rotation.set(-Math.PI / 2, 0, index * 0.61);
    piece.renderOrder = 806;
    group.add(piece);
  }
  return group;
}

function updateJ06DebrisVisual(pile) {
  const group = jobDirtVisuals.get(pile.id);
  if (!group) return;
  group.visible = !pile.captured;
  group.position.copy(pile.position);
  group.position.y = Math.max(0.012, pile.position.y);
  const direction = pile.intake.clone().sub(pile.position).setY(0);
  if (direction.lengthSq() > 1e-6) group.rotation.y = Math.atan2(direction.x, direction.z);
  const compact = 1 - pile.travel * 0.28;
  group.scale.set(0.9 + pile.travel * 0.16, 1, compact);
}

function makeJ06PanFillVisual() {
  const group = new THREE.Group();
  group.name = 'RUNTIME__dustpan_fill';
  const base = new THREE.Mesh(new THREE.CircleGeometry(0.048, 20), new THREE.MeshBasicMaterial({
    color: 0x615346, transparent: true, opacity: 0.42, depthWrite: false,
    side: THREE.DoubleSide, toneMapped: false,
  }));
  base.rotation.x = -Math.PI / 2;
  base.material.userData.baseOpacity = 0.42;
  base.scale.set(1.15, 0.66, 1);
  base.renderOrder = 811;
  group.add(base);
  const layout = J06_DEBRIS_LAYOUT;
  for (let index = 0; index < layout.length; index += 1) {
    const [x, z, radius, sides] = layout[index];
    const piece = new THREE.Mesh(new THREE.CircleGeometry(radius * 0.72, sides), new THREE.MeshStandardMaterial({
      color: [0x574b40, 0x76624f, 0x92765a][index % 3], roughness: 1,
      transparent: true, opacity: 0.94, depthWrite: false, side: THREE.DoubleSide,
    }));
    piece.material.userData.baseOpacity = 0.94;
    piece.position.set(x * 0.54, 0.002 + (index % 2) * 0.002, z * 0.42);
    piece.rotation.set(-Math.PI / 2, 0, index * 0.47);
    piece.renderOrder = 812;
    group.add(piece);
  }
  group.visible = false;
  return group;
}

function setJ06PanFillOpacity(opacity) {
  if (!jobPanFillVisual) return;
  jobPanFillVisual.traverse((object) => {
    if (object.material) object.material.opacity = opacity * (object.material.userData.baseOpacity || 1);
  });
}

function updateJ06PanFillVisual() {
  if (!jobPanFillVisual) return;
  const pan = jobProps.get('dustpan');
  if (!pan || jobPanFillLevel <= 0) {
    jobPanFillVisual.visible = false;
    return;
  }
  pan.updateMatrixWorld(true);
  const localFill = new THREE.Vector3(0.015, 0.045, 0.025).applyMatrix4(pan.matrixWorld);
  jobPanFillVisual.position.copy(localFill);
  pan.getWorldQuaternion(jobPanFillVisual.quaternion);
  jobPanFillVisual.scale.setScalar(0.68 + Math.min(3, jobPanFillLevel) * 0.12);
  jobPanFillVisual.visible = true;
  setJ06PanFillOpacity(1);
}

function updateJ06BroomPose(broom, from, to) {
  if (!broom) return;
  const dx = to.x - from.x;
  const dz = to.z - from.z;
  const length = Math.hypot(dx, dz);
  if (length < 0.002) return;
  const yaw = Math.atan2(dx, dz);
  const targetX = THREE.MathUtils.clamp(dz / length * 0.12, -0.12, 0.12);
  const targetZ = THREE.MathUtils.clamp(-0.24 - dx / length * 0.08, -0.34, -0.14);
  broom.rotation.y += Math.atan2(Math.sin(yaw - broom.rotation.y), Math.cos(yaw - broom.rotation.y)) * 0.34;
  broom.rotation.x = THREE.MathUtils.lerp(broom.rotation.x, targetX, 0.34);
  broom.rotation.z = THREE.MathUtils.lerp(broom.rotation.z, targetZ, 0.34);
  broom.position.y = J06_FLOOR_Y;
  broom.updateMatrixWorld(true);
}

function parkJ06Broom(animated = true) {
  const broom = jobProps.get('short_broom');
  if (!broom) {
    j06BroomParkPending = false;
    return Promise.resolve(false);
  }
  j06BroomParkPending = false;
  const parkedRotation = broom.userData.jobInitial?.rotation?.clone();
  if (parkedRotation) parkedRotation.z = THREE.MathUtils.degToRad(-18);
  if (!animated || isRuntimePaused() || contextLost) {
    jobPropAnimationTokens.set(broom, (jobPropAnimationTokens.get(broom) || 0) + 1);
    broom.position.copy(vec3(J06_BROOM_PARK));
    if (parkedRotation) broom.rotation.copy(parkedRotation);
    broom.updateMatrixWorld(true);
    return Promise.resolve(true);
  }
  return animateJobProp(broom, J06_BROOM_PARK, 260, 0.025, parkedRotation);
}

function animateJ06DustpanEmpty() {
  const pan = jobProps.get('dustpan');
  const bin = jobProps.get('waste_bin');
  const binCenter = objectWorldCenter(bin);
  if (!pan || !binCenter) return Promise.resolve(false);
  const token = (jobPropAnimationTokens.get(pan) || 0) + 1;
  jobPropAnimationTokens.set(pan, token);
  const start = pan.position.clone();
  const startRotation = pan.rotation.clone();
  const destination = new THREE.Vector3(binCenter.x - 0.04, Math.max(0.08, binCenter.y + 0.08), binCenter.z + 0.02);
  const holding = new THREE.Vector3(2.16, J06_FLOOR_Y, -0.58);
  const duration = protocol.getState().reducedMotion ? 140 : 520;
  let elapsedMs = 0;
  let lastAt = null;
  jobPanEmptying = true;
  jobPanEmptyProgress = 0;
  return new Promise((resolve) => {
    const tick = (now) => {
      const state = jobRound?.getState();
      if (!pan.parent || jobPropAnimationTokens.get(pan) !== token || state?.jobId !== 'J06' || state.stage === 'idle') {
        jobPanEmptying = false;
        return resolve(false);
      }
      if (isRuntimePaused() || contextLost) {
        lastAt = null;
        requestAnimationFrame(tick);
        return;
      }
      if (lastAt === null) lastAt = now;
      // Follow unpaused wall time even when software WebGL delivers sparse
      // animation frames. `lastAt` is cleared while paused above, so paused
      // time is never included and resume cannot jump ahead.
      elapsedMs += Math.max(0, now - lastAt);
      lastAt = now;
      const t = Math.min(1, elapsedMs / duration);
      jobPanEmptyProgress = t;
      const pouring = Math.min(1, t / 0.72);
      const settling = Math.max(0, (t - 0.72) / 0.28);
      const eased = 1 - ((1 - pouring) ** 3);
      if (t <= 0.72) {
        pan.position.lerpVectors(start, destination, eased);
        pan.position.y += Math.sin(Math.PI * pouring) * 0.09;
      } else {
        pan.position.lerpVectors(destination, holding, 1 - ((1 - settling) ** 3));
      }
      pan.rotation.x = startRotation.x + Math.sin(Math.PI * pouring) * 0.72 * (1 - settling);
      updateJ06PanFillVisual();
      if (jobPanFillVisual && t > 0.4) {
        const pour = Math.min(1, (t - 0.4) / 0.32);
        jobPanFillVisual.position.lerp(binCenter, pour * 0.72);
        setJ06PanFillOpacity(1 - pour);
      }
      if (t < 1) requestAnimationFrame(tick);
      else {
        pan.rotation.copy(startRotation);
        jobPanFillLevel = 0;
        jobPanEmptying = false;
        jobPanEmptyProgress = 1;
        if (jobPanFillVisual) jobPanFillVisual.visible = false;
        resolve(true);
      }
    };
    requestAnimationFrame(tick);
  });
}

function prepareDishRinsePlate(plate, round) {
  dishRinsePlateReady = false;
  dishRinseReady = (async () => {
    // The plate must not leave the basin until the sponge has reached its
    // exact parked pose; the rinse gesture depends on that separation.
    const parked = dishSpongeParked || await beginDishSpongeParking();
    if (!parked || dishRound !== round || dishRound.getState().stage !== 'rinse') return false;
    const moved = await animateDishPlateRoute(plate, [{
      position: [DISH_PLATE_CANONICAL[0], DISH_RINSE_PLATE_Y, DISH_PLATE_CANONICAL[2]],
      duration: 220,
      rotationZ: 0,
    }], round, ['rinse']);
    dishRinsePlateReady = moved && dishRound === round && dishRound.getState().stage === 'rinse';
    if (dishRinsePlateReady && dishPlate) {
      dishPlate.position.set(DISH_PLATE_CANONICAL[0], DISH_RINSE_SURFACE_Y, DISH_PLATE_CANONICAL[2]);
      dishFoam.setSurface({ center: dishPlate.position, normal: [0, 1, 0], radius: DISH_SURFACE_RADIUS });
      syncDishWater();
    }
    return dishRinsePlateReady;
  })();
  return dishRinseReady;
}

function recoverDishRinseAfterInterruption() {
  if (dishRound.getState().stage !== 'rinse' || dishRinsePlateReady || isRuntimePaused()) return;
  const serial = ++dishRinseRecoverySerial;
  const round = dishRound;
  void dishRinseReady.then((ready) => {
    if (ready || serial !== dishRinseRecoverySerial || dishRound !== round ||
        dishRound.getState().stage !== 'rinse' || isRuntimePaused()) return;
    void prepareDishRinsePlate(jobProps.get('dish_plate'), round);
  });
}

function canonicalizeDishPlate(plate, round) {
  dishCanonicalization = animateDishPlateRoute(plate, [
    {
      position: [DISH_PLATE_CANONICAL[0], DISH_RINSE_PLATE_Y, DISH_PLATE_CANONICAL[2]],
      duration: 220,
      rotationZ: 0,
    },
    { position: [...DISH_PLATE_CANONICAL], duration: 180, rotationZ: 0 },
  ], round, ['water_off']);
  return dishCanonicalization;
}

function applyDishPropStep(kind, cleaned) {
  if (jobPropsJobId !== 'J01') return;
  const plate = jobProps.get('dish_plate');
  const finishingRound = dishRound;
  if (kind === 'scrub' && dishRound.getState().stage === 'rinse') {
    void prepareDishRinsePlate(plate, finishingRound);
  }
  if (kind === 'rinse') void canonicalizeDishPlate(plate, finishingRound);
  if (kind === 'finish') {
    dishResultVisibleUntil = 0;
    dishResultPlacement = animateDishPlateRoute(plate, [
      { position: [-0.1, 0.8, -2.08], duration: 180, rotationZ: 0 },
      { position: [0.52, 0.8, -2.08], duration: 420, rotationZ: 0 },
      { position: [0.52, 1.3, -2.08], duration: 320, rotationZ: 0 },
      { position: [1.0585, 1.3, -2.27], duration: 420, rotationZ: 0 },
      { position: [1.0585, 1.3, -2.27], duration: 300, rotationZ: 89.5 },
      { position: [1.0585, 0.9131584251826877, -2.27], duration: 320, rotationZ: 89.5 },
    ], finishingRound, ['ready', 'awaiting_ack']).then((moved) => {
      if (running && moved && dishRound === finishingRound &&
          ['ready', 'awaiting_ack'].includes(dishRound.getState().stage)) {
        configureJobCamera('wash_dishes');
        dishResultVisibleUntil = performance.now() + 400;
      }
      return moved;
    });
  }
}

function applyJobPropStep(jobId, kind, completed, task = null) {
  if (jobPropsJobId !== jobId) return;
  if (jobId === 'J03' && kind === 'fold') {
    const entry = jobClothFolds.get(task?.source || `unfolded_towel_${completed}`);
    entry?.controller.setProgresses([1, 1]);
  }
  if (jobId === 'J03' && kind === 'shelf') {
    const index = Number(task?.source?.match(/(\d+)$/)?.[1] || completed - 2);
    void animateJobProp(jobProps.get(task?.source || `unfolded_towel_${index}`),
      index === 1 ? [0.555, 0.5487745021121445, -1.755]
        : [0.53, 0.7645222669937747, -1.755], 360, 0.06);
  }
  if (jobId === 'J05' && kind === 'put_away') {
    void animateJobProp(jobProps.get(task.source), task.target, 300);
  }
  const refitJ06 = (settled) => {
    if (settled && jobRound?.getState().jobId === 'J06' && jobRound.getState().stage !== 'idle') {
      configureJobCamera('job_j06');
    }
  };
  if (jobId === 'J06' && kind === 'sweep') {
    jobPanFillLevel = Math.min(3, completed);
    updateJ06PanFillVisual();
    const broom = jobProps.get('short_broom');
    if (jobPointer?.source === broom && jobPointer.kind === 'sweep') {
      j06BroomParkPending = true;
    } else {
      void parkJ06Broom().then(refitJ06);
    }
  }
  if (jobId === 'J06' && kind === 'empty') {
    void animateJ06DustpanEmpty().then(refitJ06);
  }
  if (jobId === 'J06' && kind === 'put_away') {
    const tool = jobProps.get(task.source);
    void animateJobProp(tool, task.target, 340, 0.04,
      tool?.userData.jobInitial?.rotation).then(refitJ06);
  }
}

function jobTaskKey(task) {
  if (!task) return null;
  if (task.kind === 'sort' && (J02_BOOK_SOURCES.has(task.source) || task.source === 'teddy_toy')) return task.source;
  return task.kind === 'shelf' ? task.source : task.targetId || task.source;
}

function animateDishPlateLeg(root, target, duration, round, validStages, targetRotationZ = null) {
  if (!root || !Array.isArray(target)) return Promise.resolve(false);
  const token = (jobPropAnimationTokens.get(root) || 0) + 1;
  jobPropAnimationTokens.set(root, token);
  root.visible = true;
  const start = root.position.clone();
  const destination = vec3(target);
  const startQuaternion = root.quaternion.clone();
  const destinationQuaternion = Number.isFinite(targetRotationZ)
    ? new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, THREE.MathUtils.degToRad(targetRotationZ)))
    : null;
  const effectiveDuration = protocol.getState().reducedMotion ? 0 : duration;
  const valid = () => running && root.parent && jobPropAnimationTokens.get(root) === token &&
    dishRound === round && validStages.includes(dishRound.getState().stage);
  if (!valid()) return Promise.resolve(false);
  if (effectiveDuration === 0) {
    root.position.copy(destination);
    if (destinationQuaternion) root.quaternion.copy(destinationQuaternion);
    root.updateMatrixWorld(true);
    if (renderer) renderer.render(scene, camera);
    return Promise.resolve(true);
  }
  let elapsedMs = 0;
  let lastAt = null;
  return new Promise((resolve) => {
    const tick = (now) => {
      if (!valid()) return resolve(false);
      if (isRuntimePaused() || contextLost) {
        lastAt = null;
        requestAnimationFrame(tick);
        return;
      }
      if (lastAt === null) lastAt = now;
      elapsedMs += Math.max(0, now - lastAt);
      lastAt = now;
      const t = Math.min(1, elapsedMs / effectiveDuration);
      const eased = 1 - ((1 - t) ** 3);
      root.position.lerpVectors(start, destination, eased);
      if (destinationQuaternion) root.quaternion.slerpQuaternions(startQuaternion, destinationQuaternion, eased);
      root.updateMatrixWorld(true);
      if (renderer) renderNow();
      if (t < 1) requestAnimationFrame(tick);
      else resolve(true);
    };
    requestAnimationFrame(tick);
  });
}

async function animateDishPlateRoute(plate, legs, round, validStages) {
  for (const leg of legs) {
    if (!await animateDishPlateLeg(plate, leg.position, leg.duration, round, validStages, leg.rotationZ)) {
      return false;
    }
  }
  return true;
}

function applyDishSpongePose(root, pose, bobHeight = 0) {
  if (!root || !pose) return false;
  root.position.set(pose.position[0], pose.position[1] + Math.max(0, bobHeight), pose.position[2]);
  root.quaternion.setFromUnitVectors(
    new THREE.Vector3(0, 1, 0),
    new THREE.Vector3(...pose.normal).normalize(),
  );
  root.updateMatrixWorld(true);
  return true;
}

function animateDishSpongeTravel(root, target, duration, arcHeight, targetRotation, epoch, phase) {
  if (!root || !Array.isArray(target)) return Promise.resolve(false);
  const token = (jobPropAnimationTokens.get(root) || 0) + 1;
  jobPropAnimationTokens.set(root, token);
  root.visible = true;
  const start = root.position.clone();
  const destination = new THREE.Vector3(...target);
  const startQuaternion = root.quaternion.clone();
  const destinationQuaternion = new THREE.Quaternion().setFromEuler(targetRotation);
  const effectiveDuration = protocol.getState().reducedMotion ? 0 : duration;
  dishSpongeMotionPhase = phase;
  const valid = () => root.parent && jobPropAnimationTokens.get(root) === token &&
    epoch === dishSpongeMotionEpoch && !isRuntimePaused() && !contextLost;
  if (effectiveDuration === 0) {
    if (!valid()) return Promise.resolve(false);
    root.position.copy(destination);
    root.quaternion.copy(destinationQuaternion);
    root.updateMatrixWorld(true);
    if (renderer) renderer.render(scene, camera);
    return Promise.resolve(true);
  }
  const startedAt = performance.now();
  return new Promise((resolve) => {
    const tick = (now) => {
      if (!valid()) return resolve(false);
      const t = Math.min(1, (now - startedAt) / effectiveDuration);
      const eased = 1 - ((1 - t) ** 3);
      root.position.lerpVectors(start, destination, eased);
      root.position.y += Math.sin(Math.PI * t) * Math.max(0, arcHeight);
      root.quaternion.slerpQuaternions(startQuaternion, destinationQuaternion, eased);
      root.updateMatrixWorld(true);
      if (renderer) renderNow();
      if (t < 1) requestAnimationFrame(tick);
      else resolve(true);
    };
    requestAnimationFrame(tick);
  });
}

function animateDishSpongeContact(root, fromXZ, toXZ, duration = 90, bobHeight = 0, epoch = dishSpongeMotionEpoch) {
  if (!root || !Array.isArray(fromXZ) || !Array.isArray(toXZ)) return Promise.resolve(false);
  const destinationPose = dishSpongeContactPose(toXZ[0], toXZ[1]);
  if (!destinationPose) return Promise.resolve(false);
  const token = (jobPropAnimationTokens.get(root) || 0) + 1;
  jobPropAnimationTokens.set(root, token);
  dishSpongeMotionPhase = 'contact';
  root.visible = true;
  const effectiveDuration = protocol.getState().reducedMotion ? 0 : duration;
  if (effectiveDuration === 0) {
    if (epoch !== dishSpongeMotionEpoch || isRuntimePaused() || contextLost) return Promise.resolve(false);
    applyDishSpongePose(root, destinationPose);
    dishSpongeLogicalContact = [...toXZ];
    dishSpongeParked = false;
    if (renderer) renderer.render(scene, camera);
    return Promise.resolve(true);
  }
  const startedAt = performance.now();
  return new Promise((resolve) => {
    const tick = (now) => {
      if (!root.parent || jobPropAnimationTokens.get(root) !== token || epoch !== dishSpongeMotionEpoch ||
          isRuntimePaused() || contextLost) return resolve(false);
      const t = Math.min(1, (now - startedAt) / effectiveDuration);
      const eased = 1 - ((1 - t) ** 3);
      const x = THREE.MathUtils.lerp(fromXZ[0], toXZ[0], eased);
      const z = THREE.MathUtils.lerp(fromXZ[1], toXZ[1], eased);
      const pose = dishSpongeContactPose(x, z);
      if (!pose) return resolve(false);
      applyDishSpongePose(root, pose, Math.sin(Math.PI * t) * Math.max(0, bobHeight));
      dishSpongeLogicalContact = [x, z];
      dishSpongeParked = false;
      if (renderer) renderNow();
      if (t < 1) requestAnimationFrame(tick);
      else resolve(true);
    };
    requestAnimationFrame(tick);
  });
}

async function moveDishSpongeToContact(point, duration, epoch = dishSpongeMotionEpoch) {
  if (!dishSponge || !point) return false;
  const targetXZ = [point.x, point.z];
  const targetPose = dishSpongeContactPose(...targetXZ);
  if (!targetPose) return false;
  if (dishSpongeLogicalContact) {
    return animateDishSpongeContact(dishSponge, dishSpongeLogicalContact, targetXZ, duration, 0.018, epoch);
  }
  dishSpongeParked = false;
  const level = new THREE.Euler(0, 0, 0);
  const travelY = Math.max(DISH_SPONGE_TRAVEL_Y, dishSponge.position.y);
  if (!await animateDishSpongeTravel(dishSponge, [dishSponge.position.x, travelY, dishSponge.position.z],
    90, 0, level, epoch, 'approach_lift')) return false;
  if (!await animateDishSpongeTravel(dishSponge, [targetXZ[0], travelY, targetXZ[1]],
    150, 0.025, level, epoch, 'approach_traverse')) return false;
  const targetQuaternion = new THREE.Quaternion().setFromUnitVectors(
    new THREE.Vector3(0, 1, 0), new THREE.Vector3(...targetPose.normal).normalize());
  const targetRotation = new THREE.Euler().setFromQuaternion(targetQuaternion);
  if (!await animateDishSpongeTravel(dishSponge, targetPose.position,
    110, 0, targetRotation, epoch, 'approach_lower')) return false;
  applyDishSpongePose(dishSponge, targetPose);
  dishSpongeLogicalContact = targetXZ;
  dishSpongeParked = false;
  dishSpongeMotionPhase = 'contact';
  if (renderer) renderer.render(scene, camera);
  return true;
}

function invalidateDishSpongeMotion() {
  dishSpongeMotionEpoch += 1;
  dishSpongeLogicalContact = null;
  dishSpongeMotionPhase = 'parked';
  dishSpongeParkingActive = false;
  dishSpongeParked = true;
  dishSpongeParking = Promise.resolve(false);
}

function pauseDishSpongeMotion() {
  dishSpongeMotionEpoch += 1;
  dishSpongeMotionPhase = `paused:${dishSpongeMotionPhase}`;
  if (dishSpongeParkingActive) {
    dishSpongeParkingActive = false;
    dishSpongeParking = Promise.resolve(false);
  }
}

async function parkDishSponge() {
  const root = dishSponge;
  if (!root) return false;
  const epoch = ++dishSpongeMotionEpoch;
  dishSpongeLogicalContact = null;
  dishSpongeParkingActive = true;
  dishSpongeParked = false;
  const level = new THREE.Euler(0, 0, 0);
  try {
    const travelY = Math.max(DISH_SPONGE_TRAVEL_Y, root.position.y);
    if (!await animateDishSpongeTravel(root, [root.position.x, travelY, root.position.z],
      100, 0, level, epoch, 'park_lift')) return false;
    if (!await animateDishSpongeTravel(root, [DISH_SPONGE_PARK_POSITION[0], travelY, DISH_SPONGE_PARK_POSITION[2]],
      190, 0.025, level, epoch, 'park_traverse')) return false;
    if (!await animateDishSpongeTravel(root, DISH_SPONGE_PARK_POSITION,
      120, 0, level, epoch, 'park_lower')) return false;
    root.position.fromArray(DISH_SPONGE_PARK_POSITION);
    root.quaternion.identity();
    dishSpongeParked = true;
    dishSpongeMotionPhase = 'parked';
    root.updateMatrixWorld(true);
    if (renderer) renderer.render(scene, camera);
    return true;
  } finally {
    if (epoch === dishSpongeMotionEpoch) dishSpongeParkingActive = false;
  }
}

function beginDishSpongeParking() {
  if (dishSpongeParked && !dishSpongeParkingActive) return Promise.resolve(true);
  if (!dishSpongeParkingActive) dishSpongeParking = parkDishSponge();
  return dishSpongeParking;
}

function remainingJobTasks(state = jobRound?.getState()) {
  if (!state || state.stage !== 'active') return [];
  return (JOB_TASKS[state.jobId] || []).filter((task) =>
    task.kind === state.nextStep && !jobCompletedTaskIds.has(jobTaskKey(task)));
}

function activeJobTask(state = jobRound?.getState()) {
  if (jobTapSelection?.task && state?.completed === jobTapSelection.completed) return jobTapSelection.task;
  return remainingJobTasks(state)[0] || null;
}

function jobObjectForTask(task) {
  if (!task) return null;
  return jobProps.get(task.source) || roomRoot?.getObjectByName(task.source) || null;
}

function objectWorldCenter(object) {
  if (!object) return null;
  object.updateWorldMatrix(true, true);
  const bounds = new THREE.Box3().setFromObject(object);
  if (!bounds.isEmpty()) return bounds.getCenter(new THREE.Vector3());
  return object.getWorldPosition(new THREE.Vector3());
}

function objectWorldBoundsPoints(object) {
  if (!object) return [];
  object.updateWorldMatrix(true, true);
  const bounds = new THREE.Box3().setFromObject(object);
  if (bounds.isEmpty()) return [object.getWorldPosition(new THREE.Vector3())];
  const { min, max } = bounds;
  return [
    new THREE.Vector3(min.x, min.y, min.z), new THREE.Vector3(min.x, min.y, max.z),
    new THREE.Vector3(min.x, max.y, min.z), new THREE.Vector3(min.x, max.y, max.z),
    new THREE.Vector3(max.x, min.y, min.z), new THREE.Vector3(max.x, min.y, max.z),
    new THREE.Vector3(max.x, max.y, min.z), new THREE.Vector3(max.x, max.y, max.z),
  ];
}

function placementDestination(task) {
  if (!task) return null;
  if (task.source?.startsWith('package_') && task.targetProp) {
    const bin = jobProps.get(task.targetProp);
    if (!bin) return null;
    return new THREE.Vector3(bin.position.x,
      bin.position.y + SORTING_BIN_INTERIOR_Y * bin.scale.y, bin.position.z);
  }
  return task.target ? vec3(task.target) : null;
}

function taskTargetPosition(task) {
  if (!task) return null;
  if (jobRound?.getState().jobId === 'J06' && task.kind === 'sweep') {
    const pile = jobDustPiles.get(task.targetId);
    if (pile) return pile.position.clone();
  }
  if (task.targetProp) {
    const placement = placementDestination(task);
    if (placement && task.kind === 'sort') return placement;
    const center = objectWorldCenter(jobProps.get(task.targetProp));
    if (center) return center;
  }
  return task.target ? vec3(task.target) : null;
}

function jobTargetCandidates(state = jobRound?.getState()) {
  if (!state) return [];
  const seen = new Set();
  return (JOB_TASKS[state.jobId] || []).flatMap((task) => {
    if (!task.targetId || seen.has(task.targetId) || jobOccupiedTargetIds.has(task.targetId)) return [];
    const position = taskTargetPosition(task);
    if (!position) return [];
    seen.add(task.targetId);
    return [{ id: task.targetId, position }];
  });
}

function taskAtPointer(event, state) {
  const tasks = remainingJobTasks(state);
  let best = null;
  let bestDistance = Infinity;
  for (const task of tasks) {
    const object = jobObjectForTask(task);
    if (!object) continue;
    const distance = eventDistanceToWorld(event, objectWorldCenter(object));
    if ((pointerHitsObject(event, object, 54) || distance <= 54) && distance < bestDistance) {
      best = task;
      bestDistance = distance;
    }
  }
  return best;
}

function pointerMatchesTaskTarget(event, state, task, maxRadius = 82) {
  const target = taskTargetPosition(task);
  if (!target) return false;
  const currentDistance = eventDistanceToWorld(event, target);
  if (currentDistance > maxRadius) return false;
  const nearestDistance = jobTargetCandidates(state).reduce((best, candidate) =>
    Math.min(best, eventDistanceToWorld(event, candidate.position)), Infinity);
  // Coincident targets are intentional reuse (for example the first wiped
  // zone is also the cloth's storage hook); adjacent bins still have a clear
  // nearest identity and cannot satisfy another symbol.
  return currentDistance <= nearestDistance + 1;
}

function cssPointForWorld(position) {
  if (!position) return null;
  const rect = canvas.getBoundingClientRect();
  const projected = position.clone().project(camera);
  return {
    x: rect.left + (projected.x + 1) * rect.width * 0.5,
    y: rect.top + (1 - projected.y) * rect.height * 0.5,
  };
}

function eventDistanceToWorld(event, position) {
  const point = cssPointForWorld(position);
  return point ? Math.hypot(event.clientX - point.x, event.clientY - point.y) : Infinity;
}

function makeJobGuide(position, surface, color, patch = false) {
  const geometry = patch ? new THREE.CircleGeometry(0.12, 24) : new THREE.RingGeometry(0.14, 0.205, 32);
  const material = new THREE.MeshBasicMaterial({
    color, transparent: true, opacity: patch ? 0.64 : 0.88,
    depthWrite: false, side: THREE.DoubleSide, toneMapped: false,
  });
  const mesh = new THREE.Mesh(geometry, material);
  mesh.position.copy(position);
  if (surface === 'floor') {
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.y += 0.018;
  } else {
    mesh.position.z += 0.018;
  }
  mesh.renderOrder = 850;
  return mesh;
}

function makeShelfWipeGuide(position, color) {
  const halfX = 0.125;
  const halfZ = 0.09;
  const geometry = new THREE.BufferGeometry().setFromPoints([
    new THREE.Vector3(-halfX, 0, -halfZ), new THREE.Vector3(halfX, 0, -halfZ),
    new THREE.Vector3(halfX, 0, halfZ), new THREE.Vector3(-halfX, 0, halfZ),
  ]);
  const line = new THREE.LineLoop(geometry, new THREE.LineBasicMaterial({
    color, transparent: true, opacity: 0.9, depthTest: true, depthWrite: false, toneMapped: false,
  }));
  line.position.copy(position);
  line.position.y += 0.012;
  line.renderOrder = 850;
  return line;
}

function makeJ06SweepDirectionGuide(pile) {
  if (!pile) return null;
  const start = pile.position.clone().setY(0.032);
  const direction = pile.intake.clone().sub(pile.position).setY(0);
  const length = direction.length();
  if (length < 0.05) return null;
  direction.normalize();
  const end = start.clone().addScaledVector(direction, Math.min(0.25, Math.max(0.1, length - 0.06)));
  const side = new THREE.Vector3(-direction.z, 0, direction.x);
  const back = end.clone().addScaledVector(direction, -0.045);
  const geometry = new THREE.BufferGeometry().setFromPoints([
    start, end,
    end, back.clone().addScaledVector(side, 0.035),
    end, back.clone().addScaledVector(side, -0.035),
  ]);
  const line = new THREE.LineSegments(geometry, new THREE.LineBasicMaterial({
    color: 0xf4bf4f, transparent: true, opacity: 0.9, depthTest: true, depthWrite: false,
    toneMapped: false,
  }));
  line.renderOrder = 846;
  return line;
}

function drawMatchSymbol(context, shape, color) {
  context.fillStyle = color;
  context.strokeStyle = '#4a3526';
  context.lineWidth = 8;
  context.beginPath();
  if (shape === 'circle') context.arc(64, 64, 28, 0, Math.PI * 2);
  if (shape === 'square') context.rect(36, 36, 56, 56);
  if (shape === 'triangle') {
    context.moveTo(64, 30); context.lineTo(98, 94); context.lineTo(30, 94); context.closePath();
  }
  if (shape === 'star') {
    for (let index = 0; index < 10; index += 1) {
      const angle = -Math.PI / 2 + index * Math.PI / 5;
      const radius = index % 2 ? 15 : 34;
      const x = 64 + Math.cos(angle) * radius;
      const y = 64 + Math.sin(angle) * radius;
      if (index === 0) context.moveTo(x, y); else context.lineTo(x, y);
    }
    context.closePath();
  }
  context.fill();
  context.stroke();
}

function makeBinSymbolDecal(shape, object) {
  if (!object) return null;
  const canvasTexture = document.createElement('canvas');
  canvasTexture.width = 128;
  canvasTexture.height = 128;
  const context = canvasTexture.getContext('2d');
  context.fillStyle = 'rgba(255,248,224,.98)';
  context.strokeStyle = '#6c4a31';
  context.lineWidth = 7;
  context.beginPath();
  context.roundRect(8, 8, 112, 112, 24);
  context.fill();
  context.stroke();
  const colors = { circle: '#4e9dc5', square: '#e48745', star: '#efbd3e', triangle: '#62a66d' };
  drawMatchSymbol(context, shape, colors[shape]);
  const texture = new THREE.CanvasTexture(canvasTexture);
  texture.colorSpace = THREE.SRGBColorSpace;
  const decal = new THREE.Mesh(new THREE.PlaneGeometry(0.17, 0.17), new THREE.MeshBasicMaterial({
    map: texture, transparent: true, depthTest: true, depthWrite: false, toneMapped: false,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }));
  const anchor = object.getObjectByName('anchor_label');
  object.updateWorldMatrix(true, true);
  const normal = new THREE.Vector3(0, 0, 1);
  if (anchor) {
    anchor.getWorldPosition(decal.position);
    anchor.getWorldQuaternion(decal.quaternion);
  } else {
    const bounds = new THREE.Box3().setFromObject(object);
    decal.position.set((bounds.min.x + bounds.max.x) * 0.5,
      (bounds.min.y + bounds.max.y) * 0.5, bounds.max.z);
  }
  decal.position.addScaledVector(normal.applyQuaternion(decal.quaternion), 0.004);
  decal.renderOrder = 820;
  return decal;
}

function refreshJ04Symbols(state) {
  clearGroup(jobEffectLayer);
  for (const task of JOB_TASKS.J04) {
    const shape = task.source.replace('package_', '');
    const target = makeBinSymbolDecal(shape, jobProps.get(task.targetProp));
    if (target) jobEffectLayer.add(target);
  }
}

function refreshJobGuidance() {
  clearGroup(jobGuideLayer);
  const state = jobRound?.getState();
  const task = activeJobTask(state);
  if (!state || !task || state.stage !== 'active') return;
  if (state.jobId === 'J04') refreshJ04Symbols(state);
  if (state.jobId === 'J06' && task.kind === 'sweep') {
    const arrow = makeJ06SweepDirectionGuide(jobDustPiles.get(task.targetId));
    if (arrow) jobGuideLayer.add(arrow);
  }
  const targetTasks = state.jobId === 'J04' ? (jobFeedback?.code === 'wrong_target' ? [task] : [])
    : ['J02', 'J03'].includes(state.jobId) ? remainingJobTasks(state) : [task];
  for (const targetTask of targetTasks) {
    const target = taskTargetPosition(targetTask);
    if (!target) continue;
    const color = jobFeedback ? 0xd76450 : 0xf4bf4f;
    jobGuideLayer.add(state.jobId === 'J05' && targetTask.kind === 'wipe'
      ? makeShelfWipeGuide(target, color) : makeJobGuide(target, targetTask.surface, color));
  }
  if (renderer) renderer.render(scene, camera);
}

function emitJobFeedback(code, message) {
  const state = jobRound?.getState();
  if (!state || state.stage !== 'active') return;
  jobFeedback = { code, message };
  refreshJobGuidance();
  updateJobView();
  emitJobProgress(state, { feedback: code, message });
  diagnostic('HOUSEHOLD_JOB_INPUT_REJECTED', { jobId: state.jobId, completed: state.completed, code });
}

function clearJobFeedback() {
  if (!jobFeedback) return;
  jobFeedback = null;
  refreshJobGuidance();
  updateJobView();
}

function jobWorkingPlane(task, source) {
  const anchor = objectWorldCenter(source) || new THREE.Vector3();
  if (jobRound?.getState().jobId === 'J06' && task.kind === 'sweep') {
    return new THREE.Plane(new THREE.Vector3(0, 1, 0), -J06_FLOOR_Y);
  }
  if (task.kind === 'sort') return new THREE.Plane(new THREE.Vector3(0, 1, 0), -source.position.y);
  if (task.surface === 'floor') return new THREE.Plane(new THREE.Vector3(0, 1, 0), -Math.max(0.02, taskTargetPosition(task)?.y || anchor.y));
  if (task.surface === 'vertical') return new THREE.Plane(new THREE.Vector3(0, 0, 1), -(taskTargetPosition(task)?.z || anchor.z));
  return new THREE.Plane().setFromNormalAndCoplanarPoint(camera.getWorldDirection(new THREE.Vector3()), anchor);
}

function updatePointerRay(event) {
  const rect = canvas.getBoundingClientRect();
  pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
  camera.updateMatrixWorld(true);
  raycaster.setFromCamera(pointer, camera);
}

function moveJobSourceWithPointer(event, gesture) {
  updatePointerRay(event);
  const hit = new THREE.Vector3();
  if (!raycaster.ray.intersectPlane(gesture.plane, hit)) return null;
  gesture.source.position.copy(hit);
  gesture.source.updateMatrixWorld(true);
  if (jobRound?.getState().jobId === 'J06' && gesture.source === jobProps.get('dustpan')) {
    updateJ06PanFillVisual();
  }
  if (renderer) renderer.render(scene, camera);
  return hit;
}

function restoreJobGesture(gesture) {
  if (!gesture?.source || !gesture.startPosition) return;
  if (gesture.kind === 'fold') {
    gesture.foldEntry?.controller.reset();
    if (renderer) renderer.render(scene, camera);
    return;
  }
  if (j06BroomParkPending && gesture.source === jobProps.get('short_broom')) {
    void parkJ06Broom(!isRuntimePaused() && !contextLost).then((settled) => {
      if (settled && jobRound?.getState().jobId === 'J06') configureJobCamera('job_j06');
    });
    return;
  }
  if (gesture.startScale) gesture.source.scale.copy(gesture.startScale);
  if (gesture.startRotation) gesture.source.rotation.copy(gesture.startRotation);
  void animateJobProp(gesture.source, gesture.startPosition.toArray(), 180);
}

function restoreDishGesture(gesture) {
  if (gesture?.stage === 'scrub') {
    if (gesture.startScale) gesture.source?.scale.copy(gesture.startScale);
    if (gesture.startLogicalContact) {
      const point = new THREE.Vector3(gesture.startLogicalContact[0], DISH_SPONGE_CONTACT_Y, gesture.startLogicalContact[1]);
      void moveDishSpongeToContact(point, 180);
    } else if (!gesture.moved && gesture.startPosition) {
      gesture.source.position.copy(gesture.startPosition);
      if (gesture.startRotation) gesture.source.rotation.copy(gesture.startRotation);
      dishSpongeLogicalContact = null;
      if (renderer) renderer.render(scene, camera);
    } else {
      void beginDishSpongeParking();
    }
    dishFoam.breakStroke();
    return;
  }
  restoreJobGesture(gesture);
  if (gesture?.stage === 'rinse' && gesture.startPosition && dishPlate) {
    dishPlate.position.set(gesture.startPosition.x, gesture.startPosition.y + 0.035, gesture.startPosition.z);
    dishFoam.setSurface({ center: dishPlate.position, normal: [0, 1, 0], radius: DISH_SURFACE_RADIUS });
  }
}

function minigameInteractionDiagnostics() {
  const rect = canvas.getBoundingClientRect();
  const viewport = { width: rect.width, height: rect.height, aspect: camera.aspect, fov: camera.fov };
  const insets = protocol.getState().viewportInsets;
  const offSurface = {
    x: rect.left + rect.width * (insets.left || 0) + 28,
    y: rect.top + rect.height * (insets.top || 0) + 28,
  };
  const radiusPx = (position, radius, axis = 'x') => {
    const center = cssPointForWorld(position);
    const edge = position.clone();
    edge[axis] += radius;
    const projected = cssPointForWorld(edge);
    return center && projected ? Math.hypot(center.x - projected.x, center.y - projected.y) : 0;
  };
  const dish = dishRound.getState();
  if (dish.stage !== 'idle') {
    const remaining = dishDirt.filter((entry) => !dishCleanedPatches.has(entry));
    const spot = remaining.sort((a, b) =>
      (a.userData.coverage?.coverage?.() || 0) - (b.userData.coverage?.coverage?.() || 0))[0];
    const sourceObject = dish.stage === 'rinse' ? jobProps.get('dish_plate') : jobProps.get('kitchen_sponge');
    const source = cssPointForWorld(objectWorldCenter(sourceObject));
    const streamWorld = new THREE.Vector3(DISH_WATER_NOZZLE[0],
      dish.stage === 'rinse' ? DISH_RINSE_SURFACE_Y : DISH_SURFACE_Y, DISH_WATER_NOZZLE[2]);
    const valid = dish.stage === 'water_off'
      ? cssPointForWorld(dishTap.getWorldPosition(new THREE.Vector3()))
      : dish.stage === 'rinse' ? cssPointForWorld(streamWorld)
        : cssPointForWorld((spot || dishPlate).getWorldPosition(new THREE.Vector3()));
    const foam = dishFoam.diagnostics();
    const peak = Math.max(1, foam.foamPeak || foam.foamCount || 1);
    const effects = {
      foamCount: foam.foamCount, activeBubbles: foam.activeBubbles,
      foamCapacity: foam.capacities?.foam || 0, bubbleCapacity: foam.capacities?.bubbles || 0,
      foamFill: Number((foam.foamFill || 0).toFixed(3)),
      foamResidual: Number((foam.foamCount / peak).toFixed(3)),
      rinseSamples: foam.rinseSamples || 0,
      water: dishWater?.diagnostics() || null,
    };
    const interaction = dish.stage === 'scrub' ? {
      kind: 'scrub_surface', threshold: DISH_SPOT_THRESHOLD, brushRadiusWorld: DISH_BRUSH_RADIUS,
      plate: { center: cssPointForWorld(dishPlate.getWorldPosition(new THREE.Vector3())),
        radiusPx: radiusPx(dishPlate.getWorldPosition(new THREE.Vector3()), DISH_SURFACE_RADIUS) },
      spots: dishDirt.map((entry, index) => ({
        id: entry.userData.stainId, center: cssPointForWorld(entry.getWorldPosition(new THREE.Vector3())),
        radiusPx: radiusPx(entry.getWorldPosition(new THREE.Vector3()), DISH_SPOT_RADIUS),
        coverage: Number((dishCoverageFields[index]?.coverage() || 0).toFixed(3)),
        cleaned: dishCleanedPatches.has(entry),
      })), effects,
    } : dish.stage === 'rinse' ? {
      kind: 'rinse_move', threshold: DISH_RINSE_THRESHOLD,
      rinseResidualTolerance: Number((1 - DISH_RINSE_THRESHOLD).toFixed(3)),
      source, stream: { ...cssPointForWorld(streamWorld), radiusPx: radiusPx(streamWorld, DISH_SURFACE_RADIUS) },
      rinseCoverage: Number(dishRinseProgress.toFixed(3)), effects,
    } : { kind: 'tap', effects };
    const resultProps = ['ready', 'awaiting_ack'].includes(dish.stage)
      ? ['dish_plate', 'dish_rack'].map((id) => ({ id,
        worldRoot: jobProps.get(id)?.position.toArray() || null,
        corners: objectWorldBoundsPoints(jobProps.get(id)).map(cssPointForWorld) })) : [];
    const spongeRoot = jobProps.get('kitchen_sponge');
    const spongePhysical = spongeRoot ? {
      worldRoot: spongeRoot.getWorldPosition(new THREE.Vector3()).toArray(),
      worldQuaternion: spongeRoot.getWorldQuaternion(new THREE.Quaternion()).toArray(),
      worldScale: spongeRoot.getWorldScale(new THREE.Vector3()).toArray(),
      logicalXZ: dishSpongeLogicalContact ? [...dishSpongeLogicalContact] : null,
      pointerXZ: dish.stage === 'scrub' && dishPointer?.stage === 'scrub' && dishPointer.moved && dishPointer.lastContact
        ? [dishPointer.lastContact.x, dishPointer.lastContact.z] : null,
      plateWorldRoot: jobProps.get('dish_plate')?.getWorldPosition(new THREE.Vector3()).toArray() || null,
      parkingActive: dishSpongeParkingActive,
      parked: dishSpongeParked,
      rinsePlateReady: dishRinsePlateReady,
      motionEpoch: dishSpongeMotionEpoch,
      motionPhase: dishSpongeMotionPhase,
    } : null;
    return { game: 'dishes', stage: dish.stage, completed: dish.cleaned, resultProps, spongePhysical,
      camera: { position: camera.position.toArray(), fov: camera.fov },
      targets: { source, valid, offSurface, wrong: offSurface }, interaction, viewport };
  }
  const state = jobRound?.getState();
  const task = activeJobTask(state);
  let source = cssPointForWorld(objectWorldCenter(jobObjectForTask(task)));
  let valid = cssPointForWorld(taskTargetPosition(task)) || source;
  let alternatives = jobTargetCandidates(state)
    .filter((candidate) => candidate.id !== task?.targetId)
    .map((candidate) => ({ id: candidate.id, ...cssPointForWorld(candidate.position) }));
  const choices = state ? remainingJobTasks(state).map((choice) => {
    const choiceSource = cssPointForWorld(objectWorldCenter(jobObjectForTask(choice)));
    const choiceValid = cssPointForWorld(taskTargetPosition(choice)) || choiceSource;
    return { id: state.jobId === 'J02' ? choice.source : jobTaskKey(choice), source: choiceSource, valid: choiceValid,
      alternatives: jobTargetCandidates(state).filter((candidate) => candidate.id !== choice.targetId)
        .map((candidate) => ({ id: candidate.id, ...cssPointForWorld(candidate.position) })) };
  }) : [];
  let interaction = state ? { kind: 'place', choices, completedTaskIds: [...jobCompletedTaskIds] } : null;
  if (state?.jobId === 'J02') interaction = { kind: 'free_place', choices, placedIds: [...jobCompletedTaskOrder] };
  if (state?.jobId === 'J03') {
    const towels = jobClothFoldDiagnostics();
    if (state.nextStep === 'fold') {
      const foldChoices = remainingJobTasks(state).map((choice) => {
        const edges = jobClothFoldDragPoints(jobClothFolds.get(choice.source));
        return { id: choice.source, source: edges.source, valid: edges.valid };
      });
      const activeChoice = foldChoices.find((choice) => choice.id === task?.source) || foldChoices[0];
      source = activeChoice?.source || source;
      valid = activeChoice?.valid || valid;
      alternatives = [];
      interaction = {
        kind: 'fold_drag', choices: foldChoices, towels,
        completionThreshold: J03_FOLD_COMPLETE_THRESHOLD,
        releaseBeforeThreshold: 'reset',
        mapping: '0..0.5:step0,0.5..1:step1',
        activeId: jobPointer?.kind === 'fold' ? jobPointer.task.source : null,
      };
    } else {
      interaction = { ...interaction, towels };
    }
  }
  if (state?.jobId === 'J05' && state.nextStep === 'wipe') interaction = {
    kind: 'wipe_surface', threshold: 0.7, brushRadiusWorld: 0.05,
    zones: JOB_TASKS.J05.slice(0, 3).map((zone) => ({
      id: zone.targetId, center: cssPointForWorld(vec3(zone.target)),
      radiusPx: radiusPx(vec3(zone.target), 0.12),
      coverage: Number((jobCoverageFields.get(zone.targetId)?.coverage() || 0).toFixed(3)),
      cleaned: jobCompletedTaskIds.has(zone.targetId),
    })),
  };
  if (state?.jobId === 'J06' && state.nextStep === 'sweep') {
    const piles = [...jobDustPiles.values()];
    interaction = {
      kind: 'sweep_dust', captureRadiusWorld: 0.1, requiredDirectionDot: 0.2,
      piles: piles.map((pile) => ({ id: pile.id,
        center: cssPointForWorld(pile.position), worldCenter: { x: pile.position.x, y: pile.position.y, z: pile.position.z },
        radiusPx: radiusPx(pile.position, 0.12), travel: Number(pile.travel.toFixed(3)), captured: pile.captured })),
      panIntake: { ...cssPointForWorld(piles[0]?.intake), radiusPx: piles[0] ? radiusPx(piles[0].intake, 0.1) : 0 },
    };
  }
  if (state?.jobId === 'J06') {
    interaction = {
      ...(interaction || {}), floorContactY: J06_FLOOR_Y,
      workingBounds: { ...J06_WORK_BOUNDS },
      panFill: { level: jobPanFillLevel, capacity: 3, emptying: jobPanEmptying,
        emptyProgress: Number(jobPanEmptyProgress.toFixed(3)), visible: jobPanFillVisual?.visible === true },
      broom: (() => {
        const broom = jobProps.get('short_broom');
        return broom ? { worldRoot: { x: broom.position.x, y: broom.position.y, z: broom.position.z },
          parkingPending: j06BroomParkPending,
          pointerHeld: jobPointer?.source === broom && jobPointer.kind === 'sweep' } : null;
      })(),
      pan: (() => {
        const pan = jobProps.get('dustpan');
        return pan ? { worldRoot: { x: pan.position.x, y: pan.position.y, z: pan.position.z } } : null;
      })(),
    };
  }
  return state ? { game: 'household_job', jobId: state.jobId, stage: state.stage,
    completed: state.completed, task: task ? { kind: task.kind, targetId: task.targetId } : null,
    framingProps: state.jobId === 'J04'
      ? [...new Set(JOB_TASKS.J04.flatMap((entry) => [entry.source, entry.targetProp]))]
        .map((id) => ({ id, corners: objectWorldBoundsPoints(jobProps.get(id)).map(cssPointForWorld) })) : [],
    camera: { position: camera.position.toArray(), fov: camera.fov },
    targets: { source, valid, alternatives, offSurface, wrong: offSurface }, interaction,
    placement: placementPayload(state), viewport } : null;
}

async function loadRoom(id) {
  const token = ++roomLoadToken;
  ++kitchenFridgeLoadSerial;
  kitchenFridgePending = null;
  const room = descriptor.rooms[id];
  if (!room) throw new Error(`Unknown room ${id}`);
  cancelActiveContact('room_load');
  clearGuidance();
  currentRoomId = id;
  setStatus('Загружаем комнату…');
  if (activeTween) {
    const interrupted = activeTween;
    activeTween = null;
    interrupted.resolve();
  }
  clearGroup(interactionLayer);
  interactionMeshes.length = 0;
  roomLighting?.dispose();
  roomLighting = null;
  clearGroup(roomLayer);
  ++jobPropLoadToken;
  disposeJobClothFolds();
  clearGroup(jobPropLayer);
  jobProps.clear();
  jobPropsJobId = null;
  roomRoot = null;
  const url = sameOriginUrl(room.file, descriptorUrl);
  const gltf = await loader.loadAsync(url.href);
  if (token !== roomLoadToken) {
    disposeObject(gltf.scene);
    return;
  }
  roomRoot = gltf.scene;
  roomRoot.name = room.rootNode || `ROOM__${id}`;
  applyRoomStaging(room, roomRoot);
  if (id === 'bathroom') await installBathroomBathtubQuality(roomRoot, token);
  if (id === 'kitchen') await syncKitchenFridgeQuality();
  if (token !== roomLoadToken || roomRoot !== gltf.scene) {
    disposeObject(gltf.scene);
    return;
  }
  configureTextureAnisotropy(roomRoot);
  roomLayer.add(roomRoot);
  await attachLivingRoomEnvelope({
    roomId: id,
    roomRoot,
    loadGLTF: (path) => loader.loadAsync(sameOriginUrl(path, location.href).href),
    isCurrent: () => token === roomLoadToken && roomRoot === gltf.scene,
    disposeGLTF: disposeObject,
  });
  if (token !== roomLoadToken || roomRoot !== gltf.scene) {
    disposeObject(gltf.scene);
    return;
  }
  configureTextureAnisotropy(roomRoot);
  await installRoomFloorFinish(roomRoot, id, token);
  if (id === 'living') await installLivingWallpaper(roomRoot, token);
  await installWindowGarden(roomRoot, id, token);
  if (token !== roomLoadToken || roomRoot !== gltf.scene) {
    disposeObject(gltf.scene);
    return;
  }
  await loadOptionalRoomAssets(room, roomRoot);
  if (token !== roomLoadToken || roomRoot !== gltf.scene) {
    disposeObject(gltf.scene);
    return;
  }
  await loadJobProps(room);
  if (token !== roomLoadToken || roomRoot !== gltf.scene) {
    disposeObject(gltf.scene);
    return;
  }
  updateOwnedVisibility();
  const lighting = await createRoomLighting({
    roomRoot,
    roomId: id,
    nodeTransforms: room.runtimeStaging?.nodeTransforms,
    renderer,
    loadGLTF: (path) => loader.loadAsync(sameOriginUrl(path, location.href).href),
  });
  if (token !== roomLoadToken || roomRoot !== gltf.scene) {
    lighting.dispose();
    disposeObject(gltf.scene);
    return;
  }
  roomLighting = lighting;
  for (const fixture of room.optionalFixtures || []) {
    const node = roomRoot.getObjectByName(fixture.node);
    if (!node) continue;
    roomLighting.registerOptionalFixture({
      id: fixture.id,
      node,
      color: fixture.light?.color,
      intensity: fixture.light?.intensity,
      glowMin: fixture.light?.glowMin,
      glowMax: fixture.light?.glowMax,
    });
  }
  configureCamera(room);
  buildInteractions(room);
  updateLampVisual();
  placePetAtSpawn(room);
  if (dialogueBottomFraction > 0 || previewFramingFocus) configureCamera(room);
  await updateAdoptionVisual(false);
  if (renderer) renderer.render(scene, camera);
}

async function loadPet(state) {
  const token = ++petLoadToken;
  const file = modelFileFor(state);
  const petKey = `${state.species}:${state.color}:${state.wearable || 'none'}`;
  loadingPetKey = petKey;
  const url = sameOriginUrl(`../models/${file}`, location.href);
  let gltf;
  let accessoryGLTF = null;
  try {
    gltf = await loader.loadAsync(url.href);
    await installExtendedSkinningFromGLTF(gltf);
    if (state.wearable === 'cap' || state.wearable === 'bow') {
      const accessoryUrl = sameOriginUrl(`../models/${state.wearable}-accessory.glb`, location.href);
      accessoryGLTF = await loader.loadAsync(accessoryUrl.href);
    }
  } catch (error) {
    disposeObject(accessoryGLTF?.scene);
    if (loadingPetKey === petKey) loadingPetKey = null;
    throw error;
  }
  installFacialLidCrease(gltf.scene, state.species, gltf.animations);
  if (token !== petLoadToken) {
    disposeObject(gltf.scene);
    disposeObject(accessoryGLTF?.scene);
    return;
  }
  cancelPetReaction('pet_load');
  cancelActiveContact('pet_load');
  petMixer?.stopAllAction();
  petMixer = null;
  petIdleAction = null;
  petGrowth = null;
  petClips = new Map();
  clearGroup(petLayer);
  petAccessory = null;
  for (const material of materialClones) material.dispose?.();
  materialClones.clear();
  currentPetKey = petKey;
  loadingPetKey = null;
  petModel = gltf.scene;
  petModel.name = `PET__${state.species}`;
  normalizePetModel(petModel, state.species, gltf.animations);
  applyPetTint(petModel, state.species, state.color);
  installPetCoat(petModel, state.species, state.color);
  configureTextureAnisotropy(petModel);
  prepareRoomShadows(petModel);
  petGrowth = createPetGrowthController(petModel, {
    initialStage: state.stage,
    reducedMotion: state.reducedMotion,
  });
  diagnostic(petGrowth.available ? 'PET_GROWTH_READY' : 'PET_GROWTH_UNAVAILABLE', {
    species: state.species,
    stage: state.stage,
    file,
    ...petGrowth.diagnostics(),
  });
  if (accessoryGLTF) {
    const attachment = attachPetAccessory(petModel, accessoryGLTF.scene, state.species, state.wearable);
    petAccessory = accessoryGLTF.scene;
    configureTextureAnisotropy(petAccessory);
    diagnostic('PET_ACCESSORY_PREVIEW', { species: state.species, item: state.wearable, ...attachment });
  }
  petLayer.add(petModel);
  petMixer = gltf.animations.length ? new THREE.AnimationMixer(petModel) : null;
  petClips = new Map(gltf.animations.map((clip) => [clip.name, clip]));
  if (petPreview && modelFileFor(state) !== `${MODEL_FILES[state.species]}-mobile.glb`) {
    diagnostic('PET_CANDIDATE_PREVIEW', {
      preview: petPreview,
      species: state.species,
      file,
      clips: [...petClips.keys()],
    });
  }
  placePetAtSpawn();
  if ((dialogueBottomFraction > 0 || previewFramingFocus) && roomRoot) configureCamera(roomDefinition());
  petLayer.visible = state.mode !== 'adoption' || state.adoptionOpen;
  if (state.stage > 1 && !petGrowth.available) reportStageUnavailable(state);
  if (renderer) renderer.render(scene, camera);
}

function reportStageUnavailable(state) {
  const key = `${state.species}:${state.stage}`;
  if (warnedStageKey === key) return;
  warnedStageKey = key;
  diagnostic('STAGE_VISUAL_UNAVAILABLE', {
    species: state.species,
    stage: state.stage,
    message: 'Current mobile pet asset has no authored growth-stage geometry; base proportions are preserved.',
  });
}

async function applyVisualState(changed = [], previousState = null) {
  const state = protocol.getState();
  if ((changed.includes('busy') && state.busy) || (changed.includes('mode') && state.mode !== 'home')) {
    cancelNavigation();
  }
  if (changed.some((key) => ['busy', 'mode', 'room', 'species', 'wearable'].includes(key))) {
    cancelPetReaction('state_changed');
  }
  if (changed.some((key) => ['busy', 'mode', 'room'].includes(key))) {
    if (dishRound.getState().stage !== 'idle' && dishRound.getState().stage !== 'awaiting_ack') cancelDishGame();
    if (genericJobActive() && jobRound?.getState().stage !== 'awaiting_ack') cancelJobGame();
  }
  const nextRoom = effectiveRoom(state);
  const nextPetKey = `${state.species}:${state.color}:${state.wearable || 'none'}`;
  const tasks = [];
  if (descriptor && (currentRoomId !== nextRoom || !roomRoot)) {
    roomReadyPromise = loadRoom(nextRoom).catch((error) => {
      if (currentRoomId === nextRoom) setStatus('Не удалось открыть комнату', 'error');
      reportError('ROOM_LOAD_FAILED', error, true, { room: nextRoom });
      throw error;
    });
    tasks.push(roomReadyPromise);
  } else if (descriptor && roomRoot && !anyMinigameActive() &&
      ((changed.includes('jobPeriod') && previousState?.jobPeriod !== state.jobPeriod) ||
       (changed.includes('selectedJobId') && previousState?.selectedJobId !== state.selectedJobId))) {
    tasks.push(loadJobProps(roomDefinition(nextRoom), currentJobId(state)).catch((error) => {
      reportError('JOB_PROPS_LOAD_FAILED', error, true, { room: nextRoom, jobId: currentJobId(state) });
      throw error;
    }));
  }
  if (descriptor && (currentPetKey !== nextPetKey || !petModel) && loadingPetKey !== nextPetKey) {
    petReadyPromise = loadPet(state).catch((error) => {
      setStatus('Не удалось показать питомца', 'error');
      reportError('PET_LOAD_FAILED', error, true, { species: state.species });
      throw error;
    });
    tasks.push(petReadyPromise);
  }
  if (descriptor && state.mode === 'adoption' && descriptor.rooms.living?.adoption?.asset && !adoptionRoot) {
    adoptionReadyPromise = loadAdoptionAsset(descriptor.rooms.living).catch((error) => {
      setStatus('Не удалось открыть коробку', 'error');
      reportError('ADOPTION_ASSET_LOAD_FAILED', error, true);
      throw error;
    });
    tasks.push(adoptionReadyPromise);
  }
  if (changed.includes('owned') || changed.includes('purchased')) {
    updateOwnedVisibility();
    if (roomRoot) buildInteractions(roomDefinition());
    updateLampVisual();
  }
  if (changed.some((key) => ['lampOn', 'starsOn', 'nightlightOn'].includes(key))) updateLampVisual();
  if (changed.includes('reducedMotion') || changed.includes('viewportInsets')) resize();
  if (changed.includes('reducedMotion')) dishFoam.setReducedMotion(state.reducedMotion);
  if (changed.includes('stage') || changed.includes('reducedMotion')) {
    const growth = petGrowth?.setStage(state.stage, {
      reducedMotion: state.reducedMotion,
      snap: state.reducedMotion,
    });
    if (growth?.ok) diagnostic('PET_GROWTH_STAGE', { species: state.species, stage: state.stage, ...growth });
    else if (state.stage > 1) reportStageUnavailable(state);
  }
  await Promise.allSettled(tasks);
  if ((changed.includes('mode') || (state.mode === 'adoption' && changed.includes('species'))) && roomRoot) {
    configureCamera(roomDefinition(nextRoom));
  }
  if (changed.includes('mode') || changed.includes('adoptionOpen') || changed.includes('species') || changed.includes('color')) {
    const opening = state.mode === 'adoption' && state.adoptionOpen && (!previousState?.adoptionOpen || previousState?.mode !== 'adoption');
    await updateAdoptionVisual(opening);
  }
  const visualChanged = ['mode', 'adoptionOpen', 'room', 'species', 'color', 'wearable']
    .some((key) => changed.includes(key) && previousState?.[key] !== state[key]);
  if (visualChanged || tasks.length > 0) maybeReady();
}

function maybeReady() {
  if (!descriptor || !roomRoot || !petModel || !renderer) return;
  const state = protocol.getState();
  const expectedPetKey = `${state.species}:${state.color}:${state.wearable || 'none'}`;
  if (currentRoomId !== effectiveRoom(state) || currentPetKey !== expectedPetKey) return;
  if (state.mode === 'adoption' && descriptor.rooms.living?.adoption?.asset && !adoptionRoot) return;
  if (state.mode === 'adoption' && state.adoptionOpen) configureOpenAdoptionCamera(descriptor.rooms.living);
  hideStatus();
  renderer.render(scene, camera);
  if (!readySent) {
    readySent = true;
    const renderInfo = rendererDiagnostics();
    postBridge({
      type: 'ready',
      apiVersion: API_VERSION,
      sessionId: protocol.sessionId,
      mode: state.mode,
      room: effectiveRoom(state),
      species: state.species,
      color: state.color,
      wearable: state.wearable,
      adoptionOpen: state.adoptionOpen,
      triangles: renderInfo.triangles,
      drawCalls: renderInfo.drawCalls,
      renderInfo,
    });
  } else {
    diagnostic('SCENE_READY', {
      mode: state.mode,
      room: effectiveRoom(state),
      species: state.species,
      color: state.color,
      wearable: state.wearable,
      adoptionOpen: state.adoptionOpen,
      renderer: rendererDiagnostics(),
    });
  }
}

function updateTween(now) {
  if (!activeTween) return;
  const tween = activeTween;
  // Start the clock on the first rendered frame: a slow first frame must not
  // skip the start clip or jump the pet forward.
  if (tween.lastAt !== null) tween.elapsedMs += Math.max(0, now - tween.lastAt);
  tween.lastAt = now;
  const progress = Math.min(1, tween.elapsedMs / tween.duration);
  let eased = progress < 0.5 ? 2 * progress * progress : 1 - Math.pow(-2 * progress + 2, 2) / 2;
  if (tween.locomotion) {
    const locomotion = tween.locomotion;
    const sourceTime = progress * locomotion.sourceDuration;
    let travelled;
    let phase;
    let clipTime;
    const { startSeconds: ts, stopSeconds: tp, runtimeSpeed: speed } = locomotion;
    if (sourceTime <= ts) {
      phase = 'start';
      clipTime = sourceTime;
      const u = clipTime / ts;
      travelled = speed * ts * (u ** 3 - 0.5 * u ** 4);
    } else if (sourceTime < locomotion.sourceDuration - tp) {
      phase = 'walk';
      clipTime = sourceTime - ts;
      travelled = speed * (0.5 * ts + clipTime);
    } else {
      phase = 'stop';
      clipTime = sourceTime - (locomotion.sourceDuration - tp);
      const u = clipTime / tp;
      const cruise = locomotion.sourceDuration - ts - tp;
      travelled = speed * (0.5 * ts + cruise + tp * (u - u ** 3 + 0.5 * u ** 4));
    }
    eased = THREE.MathUtils.clamp(travelled / locomotion.distance, 0, 1);
    const clip = locomotion.clips[phase];
    if (clip && locomotion.phase !== phase) {
      locomotion.action?.stop();
      locomotion.action = petMixer.clipAction(clip);
      locomotion.action.reset();
      locomotion.action.setLoop(phase === 'walk' ? THREE.LoopRepeat : THREE.LoopOnce, phase === 'walk' ? Infinity : 1);
      locomotion.action.clampWhenFinished = true;
      locomotion.action.play();
      locomotion.action.paused = true;
      locomotion.phase = phase;
      locomotion.observedPhases.push(phase);
    }
    if (locomotion.action && clip) {
      locomotion.action.time = phase === 'walk'
        ? clipTime % Math.max(clip.duration, 0.001)
        : Math.min(clipTime, clip.duration);
      petMixer.update(0);
      petGrowth?.update(0);
    }
  }
  tween.object.position.lerpVectors(tween.from, tween.to, eased);
  if (tween.arcHeight) tween.object.position.y += Math.sin(Math.PI * progress) * tween.arcHeight;
  if (progress >= 1) {
    if (tween.locomotion) {
      tween.locomotion.action?.stop();
      petMixer?.update(0);
      petGrowth?.update(0);
      lastLocomotionDiagnostics = {
        species: protocol.getState().species,
        tag: tween.tag,
        distanceMeters: +tween.locomotion.distance.toFixed(5),
        durationMs: +tween.duration.toFixed(1),
        runtimeSpeedMetersPerSecond: +tween.locomotion.runtimeSpeed.toFixed(6),
        clipTimeScale: +tween.locomotion.timeScale.toFixed(4),
        phases: [...tween.locomotion.observedPhases],
        endpointErrorMeters: +tween.object.position.distanceTo(tween.to).toFixed(7),
      };
    }
    activeTween = null;
    tween.resolve();
  }
}

function faceMovement(from, to) {
  const direction = to.clone().sub(from);
  direction.y = 0;
  if (direction.lengthSq() < 0.0001) return;
  petLayer.rotation.y = Math.atan2(direction.x, direction.z);
}

function facePetToCamera() {
  faceMovement(petLayer.position, camera.position);
}

function movePetTo(target, requestedDuration = 520, tag = 'interaction', options = {}) {
  if (!petModel) return Promise.resolve();
  const state = protocol.getState();
  const destination = target.clone();
  if (Number.isFinite(options.height)) destination.y = options.height;
  else if (tag !== 'adoption') destination.y = standingHeight(destination);
  const from = petLayer.position.clone();
  faceMovement(from, destination);
  if (activeTween) {
    const interrupted = activeTween;
    activeTween = null;
    interrupted.locomotion?.action?.stop();
    petMixer?.update(0);
    petGrowth?.update(0);
    interrupted.resolve();
  }
  if (state.reducedMotion || from.distanceTo(destination) < 0.015) {
    petLayer.position.copy(destination);
    return Promise.resolve();
  }
  const distance = from.distanceTo(destination);
  const species = state.species;
  const startClip = petClips.get(`${species}_start`);
  const walkClip = petClips.get(`${species}_walk`);
  const stopClip = petClips.get(`${species}_stop`);
  const runtimeSpeed = walkMasterSpeed(species, walkClip) * (petModel.scale.x || 1);
  const startSeconds = startClip?.duration || 1;
  const stopSeconds = stopClip?.duration || 1;
  // Start and stop each cover half their length at cruise speed.
  const rampDistance = runtimeSpeed * 0.5 * (startSeconds + stopSeconds);
  const locomotionReady = tag !== 'adoption' && !options.arcHeight && runtimeSpeed > 0
    && distance >= rampDistance && startClip && walkClip && stopClip && petMixer;
  const sourceDuration = locomotionReady
    ? startSeconds + stopSeconds + (distance - rampDistance) / runtimeSpeed : 0;
  const duration = locomotionReady
    ? Math.max(180, requestedDuration, sourceDuration * 1000 / MAX_LOCOMOTION_TIME_SCALE)
    : Math.max(180, Math.min(3000, requestedDuration));
  return new Promise((resolve) => {
    activeTween = {
      object: petLayer,
      from,
      to: destination,
      duration,
      elapsedMs: 0,
      lastAt: null,
      tag,
      arcHeight: Number.isFinite(options.arcHeight) ? Math.max(0, options.arcHeight) : 0,
      locomotion: locomotionReady ? {
        distance,
        runtimeSpeed,
        sourceDuration,
        startSeconds,
        stopSeconds,
        timeScale: sourceDuration / (duration / 1000),
        clips: { start: startClip, walk: walkClip, stop: stopClip },
        phase: null,
        observedPhases: [],
        action: null,
      } : null,
      resolve,
    };
    scheduleFrame();
  });
}

async function bodyReaction(action) {
  if (!petModel || protocol.getState().reducedMotion) return;
  const originalX = petLayer.rotation.x;
  const originalZ = petLayer.rotation.z;
  const tilt = action === 'play' ? 0.09 : 0.13;
  petLayer.rotation.x = originalX + tilt;
  petLayer.rotation.z = originalZ + (action === 'play' ? 0.05 : 0);
  await new Promise((resolve) => setTimeout(resolve, 180));
  petLayer.rotation.x = originalX;
  petLayer.rotation.z = originalZ;
}

function restoreContactProp(run) {
  if (!run?.prop || !run.propStart) return true;
  run.prop.position.copy(run.propStart.position);
  run.prop.quaternion.copy(run.propStart.quaternion);
  run.prop.scale.copy(run.propStart.scale);
  run.prop.updateMatrixWorld(true);
  return run.prop.position.distanceTo(run.propStart.position) < 1e-7
    && run.prop.quaternion.angleTo(run.propStart.quaternion) < 1e-7
    && run.prop.scale.distanceTo(run.propStart.scale) < 1e-7;
}

function resetPetActionPose(run = activeContact) {
  clearHeadAimPose(run);
  if (run) run.headAim = null;
  if (run?.finishedListener && petMixer) petMixer.removeEventListener('finished', run.finishedListener);
  if (run?.petAction) run.petAction.stop();
  if (run?.cue) {
    run.cue.action.stop();
    run.cue.resolve(false);
    run.cue = null;
  }
  petMixer?.stopAllAction();
  petMixer?.update(0);
  petGrowth?.update(0);
  petModel?.updateMatrixWorld(true);
}

function cancelActiveContact(reason = 'cancelled') {
  const run = activeContact;
  if (!run) return false;
  run.cancelled = true;
  run.cancelReason = reason;
  if (run.metrics?.scenario) {
    cancelCameraTween();
    if (roomRoot && currentRoomId === effectiveRoom(protocol.getState())) configureCamera(roomDefinition());
  }
  if (activeTween?.tag === (run.tweenTag || 'contact')) {
    const interrupted = activeTween;
    activeTween = null;
    interrupted.locomotion?.action?.stop();
    petMixer?.update(0);
    petGrowth?.update(0);
    interrupted.resolve();
  }
  const propRestored = restoreContactProp(run);
  resetPetActionPose(run);
  if (petLayer && petModel) {
    petLayer.position.copy(petHome);
    facePetToCamera();
    petLayer.updateMatrixWorld(true);
  }
  run.resolvePlayback?.(false);
  lastContactDiagnostics = {
    ...(run.metrics || {}), id: run.id, action: run.action, status: 'cancelled', reason, propRestored,
  };
  activeContact = null;
  return true;
}

function petScenarioSpec(id, room = roomDefinition()) {
  return room?.petScenarios?.find((entry) => entry.id === id) || null;
}

function cancelPetReaction(reason = 'cancelled') {
  if (!activeReaction) return false;
  if (activeReaction.listener && petMixer) petMixer.removeEventListener('finished', activeReaction.listener);
  activeReaction.action?.stop();
  activeReaction = null;
  petMixer?.update(0);
  petGrowth?.update(0);
  return true;
}

function playReaction(request = {}) {
  const kind = typeof request === 'string' ? request : request?.kind;
  const serial = typeof request === 'object' ? request?.serial : null;
  if (!['listen', 'look', 'happy'].includes(kind)) return { ok: false, reason: 'invalid_kind' };
  if (serial !== null && serial !== undefined && serial === lastReactionSerial) {
    return { ok: true, duplicate: true, serial, clip: activeReaction?.clip?.name || null };
  }
  const state = protocol.getState();
  if (state.mode !== 'home' || state.busy || protocol.getPending() || activeContact || anyMinigameActive()
      || isRuntimePaused() || contextLost || !petMixer || !petModel) {
    return { ok: false, reason: 'busy' };
  }
  const candidates = kind === 'happy'
    ? ['happy', 'petted', 'look', 'idle']
    : kind === 'listen' ? ['look', 'idle'] : ['look', 'idle'];
  const clip = candidates.map((suffix) => petClips.get(`${state.species}_${suffix}`) || petClips.get(suffix)).find(Boolean);
  if (!clip) return { ok: false, reason: 'missing_clip' };
  cancelPetReaction('superseded');
  const action = petMixer.clipAction(clip);
  action.reset();
  action.enabled = true;
  action.setLoop(THREE.LoopOnce, 1);
  action.clampWhenFinished = true;
  const reaction = { kind, serial, clip, action, listener: null };
  reaction.listener = (event) => {
    if (event.action !== action || activeReaction !== reaction) return;
    petMixer?.removeEventListener('finished', reaction.listener);
    action.stop();
    activeReaction = null;
  };
  petMixer.addEventListener('finished', reaction.listener);
  activeReaction = reaction;
  lastReactionSerial = serial;
  action.play();
  scheduleFrame();
  return { ok: true, kind, serial, clip: clip.name };
}

function scenarioApproachCamera(spec) {
  if (spec.id === 'rest_bed') {
    // Follow the pet laterally while preserving the authored view into the room.
    return { position: [-1.5, 0.48, 2.62], target: [-1.5, 0.28, -1.3], fovDegrees: 60 };
  }
  return roomDefinition().camera;
}

function scenarioActionCamera(spec) {
  return spec.camera;
}

async function runPetScenario(id) {
  const state = protocol.getState();
  const spec = petScenarioSpec(id);
  if (!spec || state.mode !== 'home' || state.room !== currentRoomId) {
    return { ok: false, reason: 'not_ready' };
  }
  const available = new Set([...state.owned, ...state.purchased]);
  if (spec.requiredOwned && !available.has(spec.requiredOwned)) return { ok: false, reason: 'not_owned' };
  if (activeContact || anyMinigameActive() || isRuntimePaused()) return { ok: false, reason: 'busy' };
  cancelPetReaction('scenario');
  const clips = (spec.clips || []).map((suffix) => petClips.get(`${state.species}_${suffix}`) || petClips.get(suffix));
  if (clips.some((clip) => !clip)) return { ok: false, reason: 'missing_clip' };
  if (state.reducedMotion) {
    diagnostic('PET_SCENARIO_REDUCED_MOTION', { scenario: id, species: state.species });
    return { ok: true, scenario: id, skippedAnimation: true };
  }
  const approach = spec.approach
    ? vec3(spec.approach)
    : nodeWorldPosition(roomRoot, spec.approachNode, petLayer.position.toArray());
  const target = spec.targetFromApproach
    ? approach.clone()
    : spec.target ? vec3(spec.target) : nodeWorldPosition(roomRoot, spec.targetNode, approach.toArray());
  const prop = spec.propNode ? findNode(roomRoot, spec.propNode) : null;
  const run = {
    token: ++contactSerial,
    id: `scenario:${id}:${contactSerial}`,
    action: id,
    normalizedAction: id,
    spec,
    prop,
    propStart: prop ? {
      position: prop.position.clone(), quaternion: prop.quaternion.clone(), scale: prop.scale.clone(),
    } : null,
    cancelled: false,
    metrics: { scenario: id, clips: clips.map((clip) => clip.name) },
  };
  activeContact = run;
  const approachCamera = scenarioApproachCamera(spec);
  const approachWalk = movePetTo(approach, 720, 'contact');
  const approachPan = moveCameraTo(approachCamera, activeTween?.duration || 720);
  await Promise.all([approachWalk, approachPan]);
  if (activeContact !== run || run.cancelled) return { ok: false, reason: run.cancelReason || 'cancelled' };
  if (!await moveCameraTo(scenarioActionCamera(spec)) || activeContact !== run || run.cancelled) {
    return { ok: false, reason: run.cancelReason || 'cancelled' };
  }
  await movePetTo(target, spec.entryArcMeters ? 720 : 620, 'contact', {
    height: spec.targetHeightMeters,
    arcHeight: spec.entryArcMeters,
  });
  if (activeContact !== run || run.cancelled) return { ok: false, reason: run.cancelReason || 'cancelled' };
  if (spec.id === 'rest_bed') {
    facePetToCamera();
  } else if (spec.faceProp && prop) {
    faceMovement(petLayer.position, new THREE.Box3().setFromObject(prop).getCenter(new THREE.Vector3()));
  } else {
    // Keep the body axis aligned with the route out of the prop. Facing the
    // close-up camera here turned larger pets diagonally through the house wall.
    faceMovement(target, approach);
  }
  if (spec.audioCue) void runtimeAudio.play(spec.audioCue);
  if (prop && Number.isFinite(spec.propScalePulse)) {
    prop.scale.multiplyScalar(spec.propScalePulse);
    prop.updateMatrixWorld(true);
  }
  for (const clip of clips) {
    run.clip = clip;
    if (!await playPetAction(run) || activeContact !== run || run.cancelled) {
      return { ok: false, reason: run.cancelReason || 'cancelled' };
    }
  }
  await movePetTo(approach, spec.entryArcMeters ? 720 : 620, 'contact', { arcHeight: spec.entryArcMeters });
  if (activeContact !== run || run.cancelled) return { ok: false, reason: run.cancelReason || 'cancelled' };
  const returnWalk = movePetTo(petHome, 720, 'contact');
  const returnPan = moveCameraTo(roomDefinition().camera, activeTween?.duration || 720);
  await Promise.all([returnWalk, returnPan]);
  if (activeContact !== run || run.cancelled) return { ok: false, reason: run.cancelReason || 'cancelled' };
  finishActiveContact(run);
  configureCamera(roomDefinition());
  facePetToCamera();
  petLayer.updateMatrixWorld(true);
  if (renderer && !isRuntimePaused() && !contextLost) renderer.render(scene, camera);
  diagnostic('PET_SCENARIO_COMPLETE', { scenario: id, species: state.species, clips: run.metrics.clips });
  return { ok: true, scenario: id, clips: run.metrics.clips };
}

function finishActiveContact(run, status = 'complete') {
  if (activeContact !== run) return;
  const propRestored = restoreContactProp(run);
  resetPetActionPose(run);
  lastContactDiagnostics = {
    ...(run.metrics || {}), id: run.id, action: run.action, status, propRestored,
  };
  activeContact = null;
}

function updateContactPropMotion() {
  const run = activeContact;
  const motion = run?.spec?.propMotion;
  if (!run?.prop || !run.propStart || !run.petAction || !run.clip || !motion || run.cancelled) return;
  const phase = run.petAction.time / Math.max(run.clip.duration, 0.001);
  const start = Number.isFinite(motion.startPhase) ? motion.startPhase : 0.5;
  if (run.action === 'play' && phase >= start && !run.contactStageSent) {
    run.contactStageSent = true;
    contactStage(run, 'paw_contact');
  }
  const finish = Number.isFinite(motion.finishPhase) ? motion.finishPhase : 1;
  const raw = THREE.MathUtils.clamp((phase - start) / Math.max(finish - start, 0.001), 0, 1);
  const progress = raw * raw * (3 - 2 * raw);
  run.prop.position.copy(run.propStart.position)
    .addScaledVector(run.propDirectionLocal, (motion.travelMeters || 0) * progress);
  run.prop.position.y += (motion.hopMeters || 0) * Math.sin(Math.PI * raw);
  run.prop.quaternion.copy(run.propStart.quaternion).multiply(
    new THREE.Quaternion().setFromAxisAngle(run.propRollAxisLocal, THREE.MathUtils.degToRad((motion.rollDegrees || 0) * progress)),
  );
  run.prop.updateMatrixWorld(true);
}

const EFFECTOR_BONES = Object.freeze({
  kitten: Object.freeze({
    front_right_paw: Object.freeze(['handR', 'f_toeR']),
    muzzle: Object.freeze(['jaw', 'face', 'spine006']),
  }),
  puppy: Object.freeze({
    front_right_paw: Object.freeze(['front_footR', 'front_toeR']),
    muzzle: Object.freeze(['jaw', 'face', 'spine011']),
  }),
  hamster: Object.freeze({
    front_right_paw: Object.freeze(['front_footR', 'front_toeR']),
    muzzle: Object.freeze(['spine011']),
  }),
});

function attributeComponent(attribute, index, lane) {
  if (lane === 0) return attribute.getX(index);
  if (lane === 1) return attribute.getY(index);
  if (lane === 2) return attribute.getZ(index);
  return attribute.getW(index);
}

function vertexBoneWeight(object, vertex, acceptedBones) {
  if (!acceptedBones?.size) return 0;
  const geometry = object.geometry;
  let total = 0;
  for (const suffix of ['', '1']) {
    const indices = geometry.getAttribute(`skinIndex${suffix}`);
    const weights = geometry.getAttribute(`skinWeight${suffix}`);
    if (!indices || !weights) continue;
    for (let lane = 0; lane < indices.itemSize; lane += 1) {
      const bone = object.skeleton.bones[attributeComponent(indices, vertex, lane)];
      if (bone && acceptedBones.has(bone.name)) total += attributeComponent(weights, vertex, lane);
    }
  }
  return total;
}

function sampledPetSurface(effector) {
  if (!petModel) return [];
  petModel.updateMatrixWorld(true);
  petLayer.updateMatrixWorld(true);
  const rows = [];
  const world = new THREE.Vector3();
  const local = new THREE.Vector3();
  const localBounds = new THREE.Box3();
  const species = protocol.getState().species;
  const acceptedBones = new Set(EFFECTOR_BONES[species]?.[effector] || []);
  petModel.traverse((object) => {
    if (!object.isSkinnedMesh) return;
    const position = object.geometry.getAttribute('position');
    for (let index = 0; index < position.count; index += 1) {
      object.getVertexPosition(index, world);
      world.applyMatrix4(object.matrixWorld);
      local.copy(world);
      petLayer.worldToLocal(local);
      rows.push({
        world: world.clone(),
        local: local.clone(),
        effectorWeight: vertexBoneWeight(object, index, acceptedBones),
      });
      localBounds.expandByPoint(local);
    }
  });
  if (localBounds.isEmpty()) return [];
  if (acceptedBones.size) {
    const weighted = rows.filter(({ effectorWeight }) => effectorWeight >= 0.22);
    if (weighted.length >= 12) return weighted.map((row) => row.world);
  }
  const size = localBounds.getSize(new THREE.Vector3());
  const center = localBounds.getCenter(new THREE.Vector3());
  return rows.filter(({ local: point }) => {
    if (effector === 'front_right_paw') {
      return point.x <= center.x + size.x * 0.04
        && point.y <= localBounds.min.y + size.y * 0.38
        && point.z >= localBounds.min.z + size.z * 0.56;
    }
    if (effector === 'muzzle') {
      return point.y >= localBounds.min.y + size.y * 0.36
        && point.z >= localBounds.min.z + size.z * 0.73;
    }
    if (effector === 'body_and_forepaws') {
      return point.y <= localBounds.min.y + size.y * 0.72
        && point.z >= localBounds.min.z + size.z * 0.42;
    }
    return true;
  }).map((row) => row.world);
}

function minimumSphereGap(points, center, radius, offset, direction) {
  let gap = Infinity;
  for (const point of points) {
    const dx = point.x + direction.x * offset - center.x;
    const dy = point.y + direction.y * offset - center.y;
    const dz = point.z + direction.z * offset - center.z;
    gap = Math.min(gap, Math.sqrt(dx * dx + dy * dy + dz * dz) - radius);
  }
  return gap;
}

function calibrateBallContact(run, points) {
  const bounds = new THREE.Box3().setFromObject(run.prop);
  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const radius = Math.min(size.x, size.y, size.z) * 0.5;
  const direction = center.clone().sub(petLayer.position).setY(0).normalize();
  const targetGap = Number.isFinite(run.spec.targetGapMeters) ? run.spec.targetGapMeters : 0.003;
  const maxPenetration = Number.isFinite(run.spec.maximumPenetrationMeters) ? run.spec.maximumPenetrationMeters : 0.002;
  let best = { offset: 0, gap: minimumSphereGap(points, center, radius, 0, direction), score: Infinity };
  for (let step = -200; step <= 200; step += 1) {
    const offset = step / 1000;
    const gap = minimumSphereGap(points, center, radius, offset, direction);
    if (gap < -maxPenetration) continue;
    const score = Math.abs(gap - targetGap) + Math.abs(offset) * 0.00001;
    if (score < best.score) best = { offset, gap, score };
  }
  petLayer.position.addScaledVector(direction, best.offset);
  petLayer.updateMatrixWorld(true);
  return {
    measuredGapMeters: +best.gap.toFixed(5),
    penetrationMeters: +Math.max(0, -best.gap).toFixed(5),
    alignmentMeters: +best.offset.toFixed(4),
    runtimePetScale: +petModel.scale.x.toFixed(6),
    maximumGapMeters: run.spec.maximumGapMeters,
    maximumPenetrationMeters: maxPenetration,
    withinTolerance: best.gap <= (run.spec.maximumGapMeters ?? 0.01) && best.gap >= -maxPenetration,
  };
}

function minimumBoxGap(points, bounds, offset, direction) {
  let gap = Infinity;
  const shifted = new THREE.Vector3();
  for (const point of points) {
    shifted.copy(point).addScaledVector(direction, offset);
    gap = Math.min(gap, bounds.distanceToPoint(shifted));
  }
  return gap;
}

function calibrateBoxContact(run, points) {
  const bounds = new THREE.Box3().setFromObject(run.prop);
  const center = bounds.getCenter(new THREE.Vector3());
  const direction = center.clone().sub(petLayer.position).setY(0).normalize();
  const targetGap = Number.isFinite(run.spec.targetGapMeters) ? run.spec.targetGapMeters : 0.003;
  let best = { offset: 0, gap: minimumBoxGap(points, bounds, 0, direction), score: Infinity };
  for (let step = -250; step <= 250; step += 1) {
    const offset = step / 1000;
    const gap = minimumBoxGap(points, bounds, offset, direction);
    const score = Math.abs(gap - targetGap) + Math.abs(offset) * 0.00001;
    if (score < best.score) best = { offset, gap, score };
  }
  petLayer.position.addScaledVector(direction, best.offset);
  petLayer.updateMatrixWorld(true);
  return {
    measuredGapMeters: +best.gap.toFixed(5),
    alignmentMeters: +best.offset.toFixed(4),
    maximumGapMeters: run.spec.maximumGapMeters ?? 0.01,
    withinTolerance: best.gap <= (run.spec.maximumGapMeters ?? 0.01),
  };
}

function measureSurfaceGap(points, prop) {
  if (!points.length || !prop) return null;
  const bounds = new THREE.Box3().setFromObject(prop);
  let gap = Infinity;
  for (const point of points) gap = Math.min(gap, bounds.distanceToPoint(point));
  return Number.isFinite(gap) ? +gap.toFixed(5) : null;
}

function measureHorizontalSurfaceGap(points, height) {
  if (!points.length || !Number.isFinite(height)) return null;
  let gap = Infinity;
  for (const point of points) gap = Math.min(gap, Math.abs(point.y - height));
  return Number.isFinite(gap) ? +gap.toFixed(5) : null;
}

function prepareContactPose(run) {
  if (!run.clip || !petMixer) return;
  const sampleAction = petMixer.clipAction(run.clip);
  sampleAction.reset();
  sampleAction.setLoop(THREE.LoopOnce, 1);
  sampleAction.clampWhenFinished = true;
  sampleAction.play();
  petMixer.setTime(run.clip.duration * (run.spec.contactPhase || 0.5));
  petModel.updateMatrixWorld(true);
  const points = sampledPetSurface(run.spec.effector);
  const effectorBounds = new THREE.Box3().setFromPoints(points);
  run.metrics = {
    ...run.metrics,
    effectorBounds: points.length ? {
      min: effectorBounds.min.toArray().map((value) => +value.toFixed(4)),
      max: effectorBounds.max.toArray().map((value) => +value.toFixed(4)),
    } : null,
  };
  if (run.action === 'play' && run.prop && points.length) {
    run.metrics = { ...run.metrics, ...calibrateBallContact(run, points), sampledVertices: points.length };
  } else if ((run.action === 'feed' || run.action === 'water') && run.prop && points.length) {
    run.metrics = {
      ...run.metrics,
      ...calibrateBoxContact(run, points),
      sampledVertices: points.length,
      runtimePetScale: +petModel.scale.x.toFixed(6),
    };
  } else {
    run.metrics = {
      ...run.metrics,
      measuredGapMeters: measureSurfaceGap(points, run.prop),
      waterSurfaceGapMeters: measureHorizontalSurfaceGap(points, run.spec.contactSurfaceHeightMeters),
      sampledVertices: points.length,
      runtimePetScale: +petModel.scale.x.toFixed(6),
    };
  }
  sampleAction.stop();
  petMixer.stopAllAction();
  petMixer.update(0);
  petGrowth?.update(0);
}

function playPetAction(run) {
  if (!run.clip || !petMixer || protocol.getState().reducedMotion) return Promise.resolve(false);
  const action = petMixer.clipAction(run.clip);
  run.petAction = action;
  action.reset();
  action.enabled = true;
  action.setLoop(THREE.LoopOnce, 1);
  action.clampWhenFinished = true;
  return new Promise((resolve) => {
    let settled = false;
    const finish = (played) => {
      if (settled) return;
      settled = true;
      if (run.finishedListener) petMixer?.removeEventListener('finished', run.finishedListener);
      run.finishedListener = null;
      run.resolvePlayback = null;
      resolve(played);
    };
    run.resolvePlayback = finish;
    run.finishedListener = (event) => {
      if (event.action === action) finish(true);
    };
    petMixer.addEventListener('finished', run.finishedListener);
    action.play();
    scheduleFrame();
  });
}

function updateContactCue() {
  const cue = activeContact?.cue;
  if (!cue) return;
  if (!cue.fading && cue.action.time >= cue.stopAtSeconds - 0.18) {
    cue.action.fadeOut(0.18);
    cue.fading = true;
  }
  if (cue.action.time >= cue.stopAtSeconds) {
    cue.action.stop();
    activeContact.cue = null;
    cue.resolve(true);
  }
}

function playContactCue(run, clip, seconds) {
  if (!clip || !petMixer || protocol.getState().reducedMotion) return Promise.resolve(true);
  const action = petMixer.clipAction(clip);
  action.reset();
  action.enabled = true;
  action.setLoop(THREE.LoopOnce, 1);
  action.clampWhenFinished = false;
  action.fadeIn(0.14);
  action.play();
  return new Promise((resolve) => {
    run.cue = { action, stopAtSeconds: Math.min(seconds, clip.duration - 0.02), fading: false, resolve };
    scheduleFrame();
  });
}

// GLTFLoader strips periods from node names for animation track bindings.
const HEAD_BONES = Object.freeze({ kitten: 'spine006', puppy: 'spine011', hamster: 'spine011' });
const HEAD_FAMILY = Object.freeze({
  kitten: Object.freeze(['spine005', 'spine006', 'face', 'jaw', 'earL', 'earL001', 'earR', 'earR001']),
  puppy: Object.freeze(['spine011', 'face', 'jaw', 'earL', 'earL001', 'earR', 'earR001']),
  hamster: Object.freeze(['spine011']),
});
const MAX_HEAD_YAW = THREE.MathUtils.degToRad(10);
const MAX_HEAD_PITCH = THREE.MathUtils.degToRad(36);

function clearHeadAimPose(run = activeContact) {
  const aim = run?.headAim;
  if (!aim?.basePose) return;
  for (const { bone, position, quaternion } of aim.basePose) {
    bone.position.copy(position);
    bone.quaternion.copy(quaternion);
  }
  aim.basePose = null;
  petModel?.updateMatrixWorld(true);
}

function startHeadAim(run, prop, stage) {
  const species = protocol.getState().species;
  const bone = petModel?.getObjectByName(HEAD_BONES[species]);
  if (!bone || !prop) return false;
  const family = HEAD_FAMILY[species].map((name) => petModel.getObjectByName(name));
  if (family.some((part) => !part || part.parent !== bone.parent)) return false;
  petModel.updateMatrixWorld(true);
  const headPosition = bone.getWorldPosition(new THREE.Vector3());
  const jawPosition = petModel.getObjectByName('jaw')?.getWorldPosition(new THREE.Vector3());
  const headWorldQuaternion = bone.getWorldQuaternion(new THREE.Quaternion());
  const petForward = new THREE.Vector3(0, 0, 1).applyQuaternion(petLayer.getWorldQuaternion(new THREE.Quaternion()));
  const jawDelta = jawPosition?.clone().sub(headPosition);
  // The jaw marker is lateral to the face centre on some rigs. It supplies
  // anatomical pitch; the facing pet root supplies the horizontal heading.
  const forwardWorld = jawDelta && jawDelta.length() > 0.01
    ? petForward.clone().multiplyScalar(Math.hypot(jawDelta.x, jawDelta.z)).setY(jawDelta.y).normalize()
    : petForward;
  const localForward = forwardWorld.clone().applyQuaternion(headWorldQuaternion.invert()).normalize();
  if (localForward.lengthSq() < 0.01) return false;
  run.metrics.gazeBasis = { source: jawPosition ? 'jaw_pitch_pet_heading' : 'pet_forward',
    head: headPosition.toArray().map((v) => +v.toFixed(3)),
    jaw: jawPosition?.toArray().map((v) => +v.toFixed(3)) };
  run.headAim = { bone, family, prop, stage, localForward, basePose: null };
  return true;
}

function stopHeadAim(run) {
  clearHeadAimPose(run);
  if (run) run.headAim = null;
}

function applyHeadAimPose() {
  const run = activeContact;
  const aim = run?.headAim;
  const cue = run?.cue;
  if (!aim || !cue) return;
  const phase = THREE.MathUtils.clamp(cue.action.time / cue.stopAtSeconds, 0, 1);
  const easeIn = THREE.MathUtils.smoothstep(phase, 0, 0.28);
  const easeOut = 1 - THREE.MathUtils.smoothstep(phase, 0.72, 1);
  const weight = Math.min(easeIn, easeOut);
  if (weight <= 0) return;
  petModel.updateMatrixWorld(true);
  const bone = aim.bone;
  const headPosition = bone.getWorldPosition(new THREE.Vector3());
  const target = new THREE.Box3().setFromObject(aim.prop).getCenter(new THREE.Vector3());
  const targetDirection = target.sub(headPosition).normalize();
  const baseForward = aim.localForward.clone().applyQuaternion(bone.getWorldQuaternion(new THREE.Quaternion())).normalize();
  const petWorldQuaternion = petLayer.getWorldQuaternion(new THREE.Quaternion());
  const inversePetWorld = petWorldQuaternion.clone().invert();
  const localBase = baseForward.clone().applyQuaternion(inversePetWorld);
  const localTarget = targetDirection.clone().applyQuaternion(inversePetWorld);
  const baseYaw = Math.atan2(localBase.x, localBase.z);
  const targetYaw = Math.atan2(localTarget.x, localTarget.z);
  const yawDifference = Math.atan2(Math.sin(targetYaw - baseYaw), Math.cos(targetYaw - baseYaw));
  const pitch = (direction) => Math.atan2(-direction.y, Math.hypot(direction.x, direction.z));
  const yaw = THREE.MathUtils.clamp(yawDifference, -MAX_HEAD_YAW, MAX_HEAD_YAW);
  const pitchDelta = THREE.MathUtils.clamp(pitch(localTarget) - pitch(localBase), -MAX_HEAD_PITCH, MAX_HEAD_PITCH);
  const correctionPet = new THREE.Quaternion().setFromEuler(new THREE.Euler(
    pitchDelta * weight, yaw * weight, 0, 'YXZ'));
  const worldCorrection = petWorldQuaternion.clone().multiply(correctionPet).multiply(inversePetWorld);
  const parentWorld = bone.parent.getWorldQuaternion(new THREE.Quaternion());
  const localCorrection = parentWorld.clone().invert().multiply(worldCorrection).multiply(parentWorld);
  const pivot = bone.position.clone();
  aim.basePose = aim.family.map((part) => ({ bone: part,
    position: part.position.clone(), quaternion: part.quaternion.clone() }));
  for (const part of aim.family) {
    part.position.sub(pivot).applyQuaternion(localCorrection).add(pivot);
    part.quaternion.premultiply(localCorrection);
  }
  petModel.updateMatrixWorld(true);
  if (weight >= 0.95) {
    const afterForward = aim.localForward.clone().applyQuaternion(bone.getWorldQuaternion(new THREE.Quaternion())).normalize();
    run.metrics.gaze ||= {};
    run.metrics.gaze[aim.stage] = {
      beforeDegrees: +THREE.MathUtils.radToDeg(baseForward.angleTo(targetDirection)).toFixed(2),
      afterDegrees: +THREE.MathUtils.radToDeg(afterForward.angleTo(targetDirection)).toFixed(2),
      yawDegrees: +THREE.MathUtils.radToDeg(yaw).toFixed(2),
      pitchDegrees: +THREE.MathUtils.radToDeg(pitchDelta).toFixed(2),
    };
  }
}

function contactStage(run, stage) {
  run.metrics.stages ||= [];
  run.metrics.stages.push(stage);
  diagnostic('ACTION_CUE_STAGE', { id: run.id, action: run.action, stage, species: protocol.getState().species });
}

async function runContact(actionRecord) {
  const state = protocol.getState();
  if (actionRecord.action === 'room') {
    if (state.room !== actionRecord.targetRoom) {
      diagnostic('ROOM_ACK_WITHOUT_STATE', { id: actionRecord.id, targetRoom: actionRecord.targetRoom });
      const result = protocol.setState({ room: actionRecord.targetRoom });
      await applyVisualState(result.changed, result.previous);
    }
    await roomReadyPromise;
    placePetAtSpawn();
    return;
  }
  if (state.room !== actionRecord.room) {
    diagnostic('CONTACT_SKIPPED_ROOM_CHANGED', { id: actionRecord.id, requestedRoom: actionRecord.room, room: state.room });
    return;
  }
  await roomReadyPromise;
  cancelActiveContact('superseded');
  cancelPetReaction('contact');
  const spec = petActionContactSpec(actionRecord.action, state);
  const normalizedAction = normalizeActionId(actionRecord.action, state);
  const target = spec?.target
    ? vec3(spec.target)
    : interactionPointFor(actionRecord.action, 'target', actionRecord.targetRoom);
  const approach = interactionPointFor(actionRecord.action, 'approach', actionRecord.targetRoom);
  target.y = roomDefinition()?.floor?.height ?? 0;
  approach.y = target.y;
  const prop = spec?.propNode ? roomRoot?.getObjectByName(spec.propNode) : null;
  const run = {
    token: ++contactSerial,
    id: actionRecord.id,
    action: actionRecord.action,
    normalizedAction,
    spec,
    clip: petActionClip(spec, state),
    prop,
    propStart: prop ? {
      position: prop.position.clone(), quaternion: prop.quaternion.clone(), scale: prop.scale.clone(),
    } : null,
    cancelled: false,
    metrics: { clip: petActionClip(spec, state)?.name || null, semantic: spec?.semantic || null },
  };
  activeContact = run;
  const playSequence = run.action === 'play' && run.clip && petMixer && !state.reducedMotion;
  const idleClip = playSequence ? petClips.get(`${state.species}_idle`) : null;
  if (playSequence && prop) {
    faceMovement(petLayer.position, new THREE.Box3().setFromObject(prop).getCenter(new THREE.Vector3()));
    contactStage(run, 'notice');
    startHeadAim(run, prop, 'notice');
    const noticed = await playContactCue(run, idleClip, 0.9);
    stopHeadAim(run);
    if (!noticed || activeContact !== run || run.cancelled) return;
  }
  if (playSequence) contactStage(run, 'approach');
  await movePetTo(target, spec?.entryArcMeters ? 720 : 260, 'contact', {
    height: spec?.targetHeightMeters,
    arcHeight: spec?.entryArcMeters,
  });
  if (activeContact !== run || run.cancelled) return;
  if (prop) {
    const propCenter = new THREE.Box3().setFromObject(prop).getCenter(new THREE.Vector3());
    if (spec?.faceCameraDuringContact) facePetToCamera();
    else faceMovement(petLayer.position, propCenter);
    const directionWorld = propCenter.clone().sub(petLayer.position).setY(0).normalize();
    const originWorld = prop.getWorldPosition(new THREE.Vector3());
    const parent = prop.parent;
    const localOrigin = parent.worldToLocal(originWorld.clone());
    const localAhead = parent.worldToLocal(originWorld.clone().add(directionWorld));
    run.propDirectionLocal = localAhead.sub(localOrigin).normalize();
    run.propRollAxisLocal = new THREE.Vector3(0, 1, 0).cross(run.propDirectionLocal).normalize();
  }
  if (playSequence) contactStage(run, 'plant');
  prepareContactPose(run);
  diagnostic('ACTION_CONTACT_MEASURED', {
    id: run.id, action: run.action, normalizedAction, clip: run.clip?.name || null, ...run.metrics,
  });
  if (actionRecord.action === 'feed') void runtimeAudio.play('dishPlace');
  if (actionRecord.action === 'water' || actionRecord.action === 'clean') {
    void runtimeAudio.play('waterRinse');
  }
  if (['lamp', 'stars', 'nightlight'].includes(actionRecord.action)) updateLampVisual();
  if (run.clip) await playPetAction(run);
  else await bodyReaction(actionRecord.action);
  if (activeContact !== run || run.cancelled) return;
  if (playSequence) {
    run.petAction?.stop();
    run.petAction = null;
    if (prop) faceMovement(petLayer.position, new THREE.Box3().setFromObject(prop).getCenter(new THREE.Vector3()));
    contactStage(run, 'watch');
    startHeadAim(run, prop, 'watch');
    const watched = await playContactCue(run, idleClip, 0.9);
    stopHeadAim(run);
    if (!watched || activeContact !== run || run.cancelled) return;
    contactStage(run, 'idle');
    if (!await playContactCue(run, idleClip, 0.55) || activeContact !== run || run.cancelled) return;
  }
  await movePetTo(approach, spec?.entryArcMeters ? 720 : 280, 'contact', {
    arcHeight: spec?.entryArcMeters,
  });
  if (activeContact !== run || run.cancelled) return;
  await movePetTo(petHome, 320, 'contact');
  if (activeContact !== run || run.cancelled) return;
  finishActiveContact(run);
  configureCamera(roomDefinition());
  facePetToCamera();
  petLayer.updateMatrixWorld(true);
  if (renderer && !isRuntimePaused() && !contextLost) renderer.render(scene, camera);
  diagnostic('ACTION_CONTACT_COMPLETE', {
    id: actionRecord.id, action: actionRecord.action, room: state.room, clip: run.clip?.name || null, ...run.metrics,
  });
}

function buildDishCloseup() {
  if (dishPlate) return;
  // The visible plate, sponge and rack are service-generated GLBs staged in
  // the room. These transparent planes only preserve direct touch targets for
  // the standalone browser fallback; they never replace visible artwork.
  const hitMaterial = new THREE.MeshBasicMaterial({
    transparent: true, opacity: 0, depthWrite: false, colorWrite: false,
    side: THREE.DoubleSide,
  });
  dishPlate = new THREE.Mesh(new THREE.PlaneGeometry(0.78, 0.62), hitMaterial);
  dishPlate.name = 'DISH__plate_hit';
  dishPlate.position.set(DISH_PLATE_CANONICAL[0], DISH_SURFACE_Y, DISH_PLATE_CANONICAL[2]);
  dishPlate.rotation.x = -Math.PI / 2;
  dishLayer.add(dishPlate);
  // The service plate's visible bowl is offset from its GLB root. Place every
  // stain on that bowl and inside the calibrated sponge-contact surface.
  const offsets = [[-0.01, 0.03], [0.03, 0.03], [0.07, 0.03], [-0.01, -0.03], [0.03, -0.03], [0.07, -0.03]];
  const stainStyles = [
    { appearance: 'sauce', color: 0xb65a36, opacity: 0.82 },
    { appearance: 'porridge', color: 0xb5966a, opacity: 0.78 },
    { appearance: 'crumbs', color: 0x6e5035, opacity: 0.9 },
  ];
  for (const [index, [x, z]] of offsets.entries()) {
    const style = stainStyles[index % stainStyles.length];
    const cleaningMask = createCleaningMask(THREE, { appearance: style.appearance, seed: index + 1 });
    const patch = new THREE.Mesh(new THREE.CircleGeometry(DISH_SPOT_RADIUS, 24), new THREE.MeshBasicMaterial({
      color: style.color, transparent: true, opacity: style.opacity,
      alphaMap: cleaningMask.texture, depthTest: false, depthWrite: false,
      side: THREE.DoubleSide, toneMapped: false,
    }));
    patch.position.set(DISH_PLATE_CENTER_XZ[0] + x, DISH_DIRT_Y, DISH_PLATE_CENTER_XZ[1] + z);
    patch.rotation.x = -Math.PI / 2;
    patch.renderOrder = 3;
    patch.material.userData.baseOpacity = style.opacity;
    patch.userData.stainId = `stain_${index + 1}`;
    patch.userData.cleaningMask = cleaningMask;
    const coverage = createCoverageField({
      center: { x: patch.position.x, z: patch.position.z }, radius: DISH_SPOT_RADIUS,
      resolution: 7, threshold: DISH_SPOT_THRESHOLD,
    });
    patch.userData.coverage = coverage;
    dishCoverageFields.push(coverage);
    dishDirt.push(patch);
    dishLayer.add(patch);
  }
  dishWater = createDishWater(THREE, {
    parent: dishLayer,
    nozzle: DISH_WATER_NOZZLE,
    contact: [DISH_WATER_NOZZLE[0], DISH_BASIN_CONTACT_Y, DISH_WATER_NOZZLE[2]],
  });
  dishTap = new THREE.Mesh(new THREE.PlaneGeometry(0.46, 0.46), hitMaterial.clone());
  dishTap.name = 'DISH__tap_hit';
  dishTap.position.set(0.16, 1.13, -2.0);
  dishLayer.add(dishTap);
  dishTapGuide = new THREE.Mesh(new THREE.RingGeometry(0.11, 0.16, 28), new THREE.MeshBasicMaterial({
    color: 0xf4bf4f, transparent: true, opacity: 0.9, depthWrite: false,
    side: THREE.DoubleSide, toneMapped: false,
  }));
  dishTapGuide.position.copy(dishTap.position);
  dishTapGuide.renderOrder = 4;
  dishTapGuide.visible = false;
  dishLayer.add(dishTapGuide);
  dishFoam.setSurface({ center: dishPlate.position, normal: [0, 1, 0], radius: DISH_SURFACE_RADIUS });
  positionDishCloseup();
}

function resetDishSurfaceState() {
  dishRinseRecoverySerial += 1;
  dishCoverageFields.forEach((field) => field.reset());
  dishDirt.forEach((patch) => patch.userData.cleaningMask?.reset());
  dishCleanedPatches.clear();
  dishRinseProgress = 0;
  dishRinsedFoam = 0;
  dishCoverageEmitAt = 0;
  dishResultVisibleUntil = 0;
  dishResultPlacement = Promise.resolve(false);
  dishRinseReady = Promise.resolve(false);
  dishRinsePlateReady = false;
  dishCanonicalization = Promise.resolve(false);
  dishFinishRequest = null;
  dishFoam.reset();
  dishWater?.reset();
  if (dishPlate) {
    dishPlate.position.set(DISH_PLATE_CANONICAL[0], DISH_SURFACE_Y, DISH_PLATE_CANONICAL[2]);
    dishFoam.setSurface({ center: dishPlate.position, normal: [0, 1, 0], radius: DISH_SURFACE_RADIUS });
  }
}

function placementTargetAtPointer(event, state, maxRadius = 82) {
  let best = null;
  let bestDistance = Infinity;
  for (const candidate of jobTargetCandidates(state)) {
    const distance = eventDistanceToWorld(event, candidate.position);
    if (distance <= maxRadius && distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

function placementTargetTasks(jobId) {
  const seen = new Set();
  return (JOB_TASKS[jobId] || []).filter((task) => {
    if (!task.targetId || seen.has(task.targetId)) return false;
    seen.add(task.targetId);
    return true;
  });
}

function placementPayload(state = jobRound?.getState()) {
  if (!state || !['J02', 'J04'].includes(state.jobId)) return null;
  const active = state.stage === 'active' && state.nextStep === 'sort';
  const sources = active ? remainingJobTasks(state).map((task) => ({
    id: task.source, label: JOB_PLACEMENT_LABELS[task.source],
  })) : [];
  const targets = active ? placementTargetTasks(state.jobId)
    .filter((task) => !jobOccupiedTargetIds.has(task.targetId))
    .map((task) => ({ id: task.targetId, label: JOB_PLACEMENT_LABELS[task.targetId] })) : [];
  return { sources, targets, busy: jobPlacementBusy };
}

function resolvedPlacementTask(state, sourceId, targetId) {
  const sourceTask = remainingJobTasks(state).find((task) => task.source === sourceId);
  const targetTask = placementTargetTasks(state.jobId).find((task) => task.targetId === targetId);
  if (!sourceTask || !targetTask) return null;
  if (state.jobId === 'J02') {
    const compatible = J02_BOOK_SOURCES.has(sourceId)
      ? J02_SHELF_TARGETS.has(targetId) : sourceId === 'teddy_toy' && targetId === 'toy_chest';
    if (!compatible) return null;
  } else if (sourceTask.targetId !== targetId) {
    return null;
  }
  return { ...sourceTask, target: targetTask.target, targetProp: targetTask.targetProp,
    targetId, placementResolved: true };
}

function dishWaterContact() {
  const plate = jobProps.get('dish_plate');
  const catchesPlate = plate && isDishSurfaceContact(
    plate.position,
    DISH_WATER_NOZZLE,
    DISH_SURFACE_RADIUS,
  );
  return [DISH_WATER_NOZZLE[0], catchesPlate ? plate.position.y + 0.035 : DISH_BASIN_CONTACT_Y, DISH_WATER_NOZZLE[2]];
}

function syncDishWater(state = dishRound.getState(), active = !['idle', 'complete', 'rejected'].includes(state.stage)) {
  if (!dishWater) return;
  dishWater.setEndpoints({ nozzle: DISH_WATER_NOZZLE, contact: dishWaterContact(), normal: [0, 1, 0] });
  dishWater.setPaused(isRuntimePaused() || contextLost);
  dishWater.setFlowing(active && state.waterOn);
}

function dishCoveragePayload() {
  const foam = dishFoam.diagnostics();
  return {
    spots: dishCoverageFields.map((field) => Number(field.coverage().toFixed(3))),
    foam: Number((foam.foamFill || 0).toFixed(3)),
    rinse: Number(dishRinseProgress.toFixed(3)),
  };
}

function recordDishRinse(rinsed) {
  dishRinsedFoam += rinsed?.clearing || 0;
  const foam = dishFoam.diagnostics();
  const peak = Math.max(1, foam.foamPeak || foam.foamCount || 1);
  // A valid stream contact is observable immediately, while foam instances
  // finish their short fade asynchronously. Keep this exposure contribution
  // small so only actual foam removal can reach the completion threshold.
  const exposure = Math.min(0.12, (foam.rinseSamples || 0) * 0.008);
  dishRinseProgress = Math.max(
    dishRinseProgress,
    exposure,
    dishRinsedFoam / peak,
    1 - foam.foamCount / peak,
  );
  return foam;
}

function emitDishCoverageProgress(force = false) {
  const now = performance.now();
  if (!force && now - dishCoverageEmitAt < 100) return;
  dishCoverageEmitAt = now;
  emitDishProgress(dishRound.getState(), { coverage: dishCoveragePayload() });
}

function configureJobCamera(actionId) {
  const action = actionDescriptor(actionId);
  const job = jobRound?.getState();
  const resultCamera = camera.aspect > 1 && ['ready', 'awaiting_ack'].includes(job?.stage)
    ? action?.landscapeResultCamera : null;
  const spec = resultCamera || action?.camera;
  if (!spec) return;
  camera.position.copy(vec3(spec.position));
  camera.fov = responsiveVerticalFov(Number.isFinite(spec.fovDegrees) ? spec.fovDegrees : 55);
  camera.near = Number.isFinite(spec.near) ? spec.near : 0.05;
  camera.far = Number.isFinite(spec.far) ? spec.far : 30;
  camera.lookAt(vec3(spec.target));
  camera.updateProjectionMatrix();
  // Completed props are no longer input targets. Use the authored room view
  // instead of expanding their spread into the narrow active HUD work area.
  if (!resultCamera) frameMinigameForInsets();
  positionDishCloseup();
}

function activeMinigameFocusPoints() {
  const dish = dishRound.getState();
  if (dish.stage !== 'idle') {
    if (['ready', 'awaiting_ack'].includes(dish.stage)) {
      return ['dish_plate', 'dish_rack'].flatMap((id) => objectWorldBoundsPoints(jobProps.get(id)));
    }
    const sourceObject = dish.stage === 'rinse' ? jobProps.get('dish_plate') : jobProps.get('kitchen_sponge');
    const source = objectWorldCenter(sourceObject);
    if (dish.stage === 'scrub') {
      return [source, ...dishDirt.filter((patch) => patch.visible)
        .map((patch) => patch.getWorldPosition(new THREE.Vector3()))].filter(Boolean);
    }
    const targetObject = dish.stage === 'water_off' ? dishTap : dishPlate;
    return [source, targetObject?.getWorldPosition(new THREE.Vector3())].filter(Boolean);
  }
  const state = jobRound?.getState();
  const tasks = remainingJobTasks(state);
  if (state?.jobId === 'J04' && ['active', 'ready', 'awaiting_ack'].includes(state.stage)) {
    const ids = JOB_TASKS.J04.flatMap((task) => [task.source, task.targetProp]);
    return [...new Set(ids)].flatMap((id) => objectWorldBoundsPoints(jobProps.get(id)));
  }
  if (state?.jobId === 'J02' && ['ready', 'awaiting_ack'].includes(state.stage)) {
    return ['single_book', 'single_book_2', 'teddy_toy', 'toy_chest']
      .flatMap((id) => objectWorldBoundsPoints(jobProps.get(id)));
  }
  if (state?.jobId === 'J06' && state.stage !== 'idle') {
    const broom = jobProps.get('short_broom');
    const pan = jobProps.get('dustpan');
    const bin = jobProps.get('waste_bin');
    const activeSource = tasks[0] ? jobObjectForTask(tasks[0]) : null;
    const points = state.stage === 'awaiting_ack'
      ? [...objectWorldBoundsPoints(broom), ...objectWorldBoundsPoints(pan)]
      : state.nextStep === 'sweep'
        ? [...objectWorldBoundsPoints(broom), ...objectWorldBoundsPoints(pan)]
        : objectWorldBoundsPoints(activeSource);
    if (state.nextStep === 'empty') {
      points.push(...objectWorldBoundsPoints(bin));
      const binCenter = objectWorldCenter(bin);
      if (binCenter) points.push(
        binCenter.clone().add(new THREE.Vector3(0.23, 0, 0)),
        binCenter.clone().add(new THREE.Vector3(-0.23, 0, 0)),
        binCenter.clone().add(new THREE.Vector3(0, 0, 0.23)),
        binCenter.clone().add(new THREE.Vector3(0, 0, -0.23)),
      );
    }
    if (state.nextStep === 'put_away' && tasks[0]?.source === 'short_broom') {
      const panCenter = objectWorldCenter(pan);
      if (panCenter) points.push(panCenter);
    }
    for (const task of tasks) {
      const target = taskTargetPosition(task);
      if (target) {
        points.push(target);
        if (task.kind === 'sweep') {
          points.push(target.clone().add(new THREE.Vector3(0.1, 0, 0)),
            target.clone().add(new THREE.Vector3(-0.1, 0, 0)),
            target.clone().add(new THREE.Vector3(0, 0, 0.1)),
            target.clone().add(new THREE.Vector3(0, 0, -0.1)));
        } else {
          const guideRadius = 0.23;
          const vertical = task.surface === 'vertical';
          points.push(target.clone().add(new THREE.Vector3(guideRadius, 0, 0)),
            target.clone().add(new THREE.Vector3(-guideRadius, 0, 0)),
            target.clone().add(new THREE.Vector3(0, vertical ? guideRadius : 0, vertical ? 0 : guideRadius)),
            target.clone().add(new THREE.Vector3(0, vertical ? -guideRadius : 0, vertical ? 0 : -guideRadius)));
        }
      }
    }
    if (state.stage === 'awaiting_ack') {
      points.push(vec3(JOB_TASKS.J06[4].target), vec3(JOB_TASKS.J06[5].target));
    }
    return points;
  }
  if (state?.jobId === 'J05' && state.nextStep === 'wipe') {
    const guideRadiusX = 0.145;
    const guideRadiusZ = 0.11;
    return tasks.flatMap((task) => {
      const target = taskTargetPosition(task);
      return [objectWorldCenter(jobObjectForTask(task)), target,
        target?.clone().add(new THREE.Vector3(guideRadiusX, 0, 0)),
        target?.clone().add(new THREE.Vector3(-guideRadiusX, 0, 0)),
        target?.clone().add(new THREE.Vector3(0, 0, guideRadiusZ)),
      target?.clone().add(new THREE.Vector3(0, 0, -guideRadiusZ))].filter(Boolean);
    });
  }
  if (state?.jobId === 'J03') {
    const points = tasks.flatMap((task) => objectWorldBoundsPoints(jobObjectForTask(task)));
    if (state.nextStep === 'shelf') points.push(...objectWorldBoundsPoints(jobProps.get('towel_shelf')));
    return points;
  }
  return tasks.flatMap((task) =>
    [objectWorldCenter(jobObjectForTask(task)), taskTargetPosition(task)]).filter(Boolean);
}

function frameMinigameForInsets() {
  const points = activeMinigameFocusPoints();
  if (!points.length) return;
  const { top, bottom, left = 0, right = 0 } = protocol.getState().viewportInsets;
  const desiredX = left - right;
  const desiredY = bottom - top;
  const center = points.reduce((sum, point) => sum.add(point), new THREE.Vector3()).multiplyScalar(1 / points.length);
  camera.lookAt(center);
  camera.updateMatrixWorld(true);
  const distance = camera.position.distanceTo(center);
  const halfHeight = distance * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  const rightAxis = new THREE.Vector3(1, 0, 0).applyQuaternion(camera.quaternion);
  const upAxis = new THREE.Vector3(0, 1, 0).applyQuaternion(camera.quaternion);
  const lookTarget = center.clone()
    .addScaledVector(rightAxis, -desiredX * halfHeight * camera.aspect)
    .addScaledVector(upAxis, -desiredY * halfHeight);
  camera.lookAt(lookTarget);
  const rect = canvas.getBoundingClientRect();
  const safeHalfX = Math.max(0.06, 1 - left - right - (48 / Math.max(1, rect.width)));
  const safeHalfY = Math.max(0.06, 1 - top - bottom - (48 / Math.max(1, rect.height)));
  const maxFov = camera.aspect > 1
    ? (jobRound?.getState().jobId === 'J05' ? 65 : jobRound?.getState().jobId === 'J03' ? 60 : 55)
    : top + bottom > 0.7 ? 82 : 68;
  for (let attempt = 0; attempt < 10; attempt += 1) {
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld(true);
    const fits = points.every((point) => {
      const projected = point.clone().project(camera);
      return Math.abs(projected.x - desiredX) <= safeHalfX && Math.abs(projected.y - desiredY) <= safeHalfY;
    });
    if (fits || camera.fov >= maxFov) break;
    camera.fov = Math.min(maxFov, camera.fov * 1.1);
  }
  camera.updateProjectionMatrix();
  const job = jobRound?.getState();
  if (['ready', 'awaiting_ack'].includes(dishRound.getState().stage) ||
      (['J02', 'J04'].includes(job?.jobId) && ['active', 'ready', 'awaiting_ack'].includes(job.stage))) {
    // The dish result or room-wide placement choices can exceed the FOV ceiling.
    // Retreat only as far as their actual bounds require, keeping the HUD's
    // off-centre safe area fixed instead of cropping the completed result.
    camera.updateMatrixWorld(true);
    const tangent = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    let retreat = 0;
    for (const point of points) {
      const local = point.clone().applyMatrix4(camera.matrixWorldInverse);
      const depth = -local.z;
      retreat = Math.max(retreat,
        Math.abs(local.x / (tangent * camera.aspect) - desiredX * depth) / safeHalfX - depth,
        Math.abs(local.y / tangent - desiredY * depth) / safeHalfY - depth);
    }
    if (retreat > 0) {
      const offset = new THREE.Vector3(-desiredX * tangent * camera.aspect, -desiredY * tangent, 1)
        .applyQuaternion(camera.quaternion).multiplyScalar(retreat + 0.005);
      camera.position.add(offset);
      camera.updateMatrixWorld(true);
    }
  }
}

function emitDishProgress(state = dishRound.getState(), extra = {}) {
  postBridge({
    type: 'minigame', game: 'dishes', stage: state.stage === 'ready' ? 'water_off' : state.stage,
    cleaned: state.cleaned, total: state.total, waterOn: state.waterOn,
    coverage: dishCoveragePayload(), ...extra,
  });
}

function emitDishFeedback(code, message) {
  const state = dishRound.getState();
  emitDishProgress(state, { feedback: code, message });
  dishInstruction.textContent = message;
  diagnostic('DISH_INPUT_REJECTED', { stage: state.stage, cleaned: state.cleaned, code });
}

function updateDishView() {
  const state = dishRound.getState();
  const active = !['idle', 'complete', 'rejected'].includes(state.stage);
  // Flutter renders the accessible HUD; the HTML controls are a standalone-browser fallback.
  dishUi.hidden = !active || bridgeAvailable();
  dishLayer.visible = active;
  dishDirt.forEach((patch) => {
    patch.material.opacity = patch.material.userData.baseOpacity || 0.9;
    patch.visible = state.stage === 'scrub' && !dishCleanedPatches.has(patch);
  });
  syncDishWater(state, active);
  if (dishTapGuide) dishTapGuide.visible = active && state.stage === 'water_off';
  if (!active) return;
  dishEyebrow.textContent = 'Работа по дому · кухня';
  const messages = {
    scrub: ['Намыль тарелку', `Чистых пятен: ${state.cleaned} из 6`, 'Намылить пятно'],
    rinse: ['Проведи тарелкой под струёй', `Смыто ${Math.round(dishRinseProgress * 100)}% пены`, 'Смыть пену'],
    water_off: ['Выключи воду', 'Тарелка вымыта', 'Выключить воду'],
    awaiting_ack: ['Работа выполнена', 'Сохраняем результат…', 'Готово'],
  };
  const [instruction, progress, button] = messages[state.stage] || messages.awaiting_ack;
  dishInstruction.textContent = instruction;
  dishProgress.textContent = progress;
  dishStepButton.textContent = button;
  dishStepButton.disabled = state.stage === 'awaiting_ack' || !!dishAccessibleStepPending;
  dishCancelButton.disabled = state.stage === 'awaiting_ack';
  if (renderer) renderer.render(scene, camera);
}

async function startDishGame(source = 'flutter_hud') {
  let state = protocol.getState();
  const round = dishRound.getState();
  if (round.stage !== 'idle' || genericJobActive()) return { ok: false, reason: 'already_active' };
  if (state.mode !== 'home' || state.room !== 'kitchen') return { ok: false, reason: 'wrong_room', requiredRoom: 'kitchen' };
  if (!state.jobsAllowed || state.jobPeriod < 1) return { ok: false, reason: 'job_locked' };
  if (state.busy || protocol.getPending()) return { ok: false, reason: 'busy' };
  await Promise.all([roomReadyPromise, petReadyPromise]);
  state = protocol.getState();
  if (!roomRoot || !petModel || currentRoomId !== 'kitchen' || isRuntimePaused() || contextLost) {
    return { ok: false, reason: 'scene_loading' };
  }
  if (jobPropsJobId !== 'J01') {
    await loadJobProps(roomDefinition('kitchen'), 'J01');
    state = protocol.getState();
    if (state.room !== 'kitchen' || state.mode !== 'home' || jobPropsJobId !== 'J01') {
      return { ok: false, reason: 'scene_loading' };
    }
  }
  resetJobPropVisuals();
  accessibleMinigameToken += 1;
  dishAccessibleStepPending = null;
  buildDishCloseup();
  resetDishSurfaceState();
  dishFoam.setReducedMotion(state.reducedMotion);
  dishSponge = jobProps.get('kitchen_sponge');
  invalidateDishSpongeMotion();
  dishJobPeriod = state.jobPeriod;
  dishRound.start();
  updateDishView();
  configureJobCamera('wash_dishes');
  void movePetTo(interactionPointFor('wash_dishes', 'approach'), 460);
  emitDishProgress();
  diagnostic('DISH_GAME_STARTED', { source, jobPeriod: dishJobPeriod });
  return { ok: true, game: 'dishes' };
}

function dishStep(kind, cleanedPatch = null, canonicalReady = false) {
  if (isRuntimePaused() || contextLost) return { ok: false, reason: 'paused' };
  if (kind === 'finish' && !canonicalReady) return { ok: false, reason: 'canonicalizing', ...dishRound.getState() };
  let completedPatch = null;
  if (kind === 'scrub' && dishRound.getState().stage === 'scrub') {
    const patch = cleanedPatch || dishDirt.find((entry) => !dishCleanedPatches.has(entry));
    if (!patch || dishCleanedPatches.has(patch) || !patch.userData.coverage?.complete?.()) {
      return { ok: false, reason: 'coverage_incomplete', ...dishRound.getState() };
    }
    completedPatch = patch;
  }
  const result = dishRound.step(kind);
  if (!result.ok) return { ok: false, reason: 'wrong_stage', ...result };
  if (completedPatch) dishCleanedPatches.add(completedPatch);
  applyDishPropStep(kind, result.cleaned);
  if (kind === 'scrub' && result.stage === 'rinse') {
    runtimeAudio.stopContact();
  }
  if (kind === 'rinse') {
    runtimeAudio.stopContact();
    dishFoam.finishRinse();
  }
  if (kind === 'finish') {
    runtimeAudio.stopContact();
    void runtimeAudio.play('faucetOff');
    void runtimeAudio.play('dishPlace');
  }
  updateDishView();
  if (kind !== 'scrub' || result.stage === 'rinse') configureJobCamera('wash_dishes');
  if (result.stage !== 'ready') {
    emitDishCoverageProgress(true);
    return result;
  }
  const state = protocol.getState();
  if (state.room !== 'kitchen' || state.mode !== 'home' || state.jobPeriod !== dishJobPeriod) {
    cancelDishGame();
    return { ok: false, reason: 'state_changed' };
  }
  const started = protocol.beginAction({ action: 'wash_dishes', room: 'kitchen', source: 'minigame' });
  if (!started.ok) {
    cancelDishGame();
    return started;
  }
  dishRound.markRequested();
  protocol.markRequested(started.action.id);
  updateDishView();
  emitDishProgress();
  postBridge({
    type: 'action', id: started.action.id, action: 'wash_dishes', room: 'kitchen',
    jobPeriod: dishJobPeriod, proof: { cleaned: 6, rinsed: true, waterOff: true },
  });
  return { ok: true, stage: 'awaiting_ack', id: started.action.id };
}

function requestDishFinish() {
  const round = dishRound;
  if (round.getState().stage !== 'water_off') {
    return Promise.resolve({ ok: false, reason: 'wrong_stage', ...round.getState() });
  }
  if (dishFinishRequest) return dishFinishRequest;
  const request = (async () => {
    const canonical = await dishCanonicalization;
    if (!canonical || isRuntimePaused() || contextLost || dishRound !== round ||
        round.getState().stage !== 'water_off') {
      return { ok: false, reason: isRuntimePaused() || contextLost ? 'paused' : 'cancelled', ...round.getState() };
    }
    return dishStep('finish', null, true);
  })();
  dishFinishRequest = request;
  void request.then((result) => {
    if (!result.ok && dishFinishRequest === request && dishRound === round &&
        round.getState().stage === 'water_off') dishFinishRequest = null;
  });
  return request;
}

function cancelDishGame() {
  const wasActive = dishRound.getState().stage !== 'idle';
  const result = dishRound.cancel();
  if (!result.ok) return { ok: false, reason: 'awaiting_ack' };
  if (wasActive) void runtimeAudio.play('uiBack');
  runtimeAudio.stopContact();
  accessibleMinigameToken += 1;
  dishAccessibleStepPending = null;
  if (wasActive) {
    invalidateDishSpongeMotion();
    resetJobPropVisuals();
  }
  if (wasActive) configureCamera(roomDefinition());
  dishRound = createDishRound();
  resetDishSurfaceState();
  dishJobPeriod = 0;
  dishPointer = null;
  updateDishView();
  emitDishProgress();
  if (protocol.getState().room === 'kitchen') void movePetTo(petHome, 320);
  return { ok: true };
}

function jobIdForAction(action) {
  return /^job_j0[1-6]$/.test(action) ? action.slice(4).toUpperCase() : null;
}

function resetJobClothSoil() {
  for (const entry of jobClothMaterialState) {
    entry.material.color.copy(entry.baseColor);
    entry.material.roughness = entry.baseRoughness;
    entry.material.needsUpdate = true;
  }
  jobClothMaterialState.length = 0;
}

function prepareJobClothSoil() {
  resetJobClothSoil();
  const cloth = jobProps.get('wiping_cloth');
  if (!cloth) return;
  cloth.traverse((object) => {
    if (!object.isMesh || !object.material) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    const clones = materials.map((material) => material.clone());
    object.material = Array.isArray(object.material) ? clones : clones[0];
    for (const material of clones) {
      if (!material.color) continue;
      jobClothMaterialState.push({ material, baseColor: material.color.clone(), baseRoughness: material.roughness });
    }
  });
}

function updateJobClothSoil() {
  if (!jobClothMaterialState.length) return;
  const fields = [...jobCoverageFields.values()];
  const collected = fields.length ? fields.reduce((sum, field) => sum + field.coverage(), 0) / fields.length : 0;
  const dust = new THREE.Color(0x8b8172);
  for (const entry of jobClothMaterialState) {
    entry.material.color.copy(entry.baseColor).lerp(dust, Math.min(0.24, collected * 0.24));
    entry.material.roughness = Math.min(1, entry.baseRoughness + collected * 0.12);
    entry.material.needsUpdate = true;
  }
}

function initializeJobInteractionState(jobId) {
  jobCompletedTaskIds.clear();
  jobCompletedTaskOrder.length = 0;
  jobOccupiedTargetIds.clear();
  jobPlacementBusy = false;
  activeJobPlacement = null;
  jobPlacementSerial += 1;
  jobCoverageFields.clear();
  jobDustPiles.clear();
  jobDirtVisuals.clear();
  clearGroup(jobEffectLayer);
  jobPanFillVisual = null;
  jobPanFillLevel = 0;
  jobPanEmptying = false;
  jobPanEmptyProgress = 0;
  j06BroomParkPending = false;
  if (jobId === 'J05') {
    prepareJobClothSoil();
    for (const [index, task] of JOB_TASKS.J05.slice(0, 3).entries()) {
      const field = createCoverageField({
        center: { x: task.target[0], z: task.target[2] }, radius: 0.12,
        resolution: 7, threshold: 0.7,
      });
      jobCoverageFields.set(task.targetId, field);
      const cleaningMask = createCleaningMask(THREE, { appearance: 'dust', seed: index + 1 });
      const patch = new THREE.Mesh(new THREE.PlaneGeometry(0.25, 0.18), new THREE.MeshStandardMaterial({
        color: 0xc2b9a8, alphaMap: cleaningMask.texture, transparent: true, opacity: 0.55,
        roughness: 1, metalness: 0, depthWrite: false, side: THREE.DoubleSide,
        polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
      }));
      patch.position.set(task.target[0], task.target[1] + 0.006, task.target[2]);
      patch.rotation.x = -Math.PI / 2;
      patch.renderOrder = 810;
      patch.userData.cleaningMask = cleaningMask;
      jobDirtVisuals.set(task.targetId, patch);
      jobEffectLayer.add(patch);
    }
  }
  if (jobId === 'J06') {
    const intake = vec3(J06_PAN_INTAKE);
    for (const [index, task] of JOB_TASKS.J06.slice(0, 3).entries()) {
      const position = vec3(task.target);
      const pile = {
        id: task.targetId, position, start: position.clone(), intake: intake.clone(),
        initialDistance: Math.hypot(position.x - intake.x, position.z - intake.z),
        captured: false, travel: 0,
      };
      jobDustPiles.set(task.targetId, pile);
      const debris = makeJ06DebrisCluster(task.targetId, index);
      jobDirtVisuals.set(task.targetId, debris);
      jobEffectLayer.add(debris);
      updateJ06DebrisVisual(pile);
    }
    jobPanFillVisual = makeJ06PanFillVisual();
    jobEffectLayer.add(jobPanFillVisual);
    updateJ06PanFillVisual();
  }
}

function jobInteractionProgress(state = jobRound?.getState()) {
  if (!state) return {};
  const base = { completedTaskIds: [...jobCompletedTaskIds] };
  if (state.jobId === 'J02') return { ...base, placedIds: [...jobCompletedTaskOrder],
    occupiedTargetIds: [...jobOccupiedTargetIds] };
  if (state.jobId === 'J04') return { ...base, placedIds: [...jobCompletedTaskOrder],
    occupiedTargetIds: [...jobOccupiedTargetIds] };
  if (state.jobId === 'J05') return {
    ...base,
    coverage: Object.fromEntries([...jobCoverageFields].map(([id, field]) => [id, Number(field.coverage().toFixed(3))])),
  };
  if (state.jobId === 'J06') return {
    ...base,
    piles: [...jobDustPiles.values()].map((pile) => ({ id: pile.id, travel: Number(pile.travel.toFixed(3)), captured: pile.captured })),
    panFill: { level: jobPanFillLevel, capacity: 3, emptying: jobPanEmptying,
      emptyProgress: Number(jobPanEmptyProgress.toFixed(3)) },
  };
  return base;
}

function emitJobProgress(state = jobRound?.getState(), extra = {}) {
  if (!state) return;
  const placement = placementPayload(state);
  postBridge({ type: 'minigame', game: 'household_job', ...state, ...jobInteractionProgress(state),
    ...(placement ? { placement } : {}), ...extra });
}

function updateJobView() {
  if (!jobRound) return;
  const state = jobRound.getState();
  const active = !['idle', 'complete', 'rejected'].includes(state.stage);
  dishUi.hidden = !active || bridgeAvailable();
  dishLayer.visible = false;
  if (!active) return;
  const labels = {
    sort: ['Выбери предмет и его место', 'Убрать предмет'],
    fold: ['Сложи полотенце большой кнопкой', 'Сложить полотенце'],
    shelf: ['Положи сложенное полотенце на полку', 'На полку'],
    wipe: ['Протри отмеченный участок полки', 'Протереть участок'],
    sweep: ['Смети пыль в совок', 'Подмести участок'],
    empty: ['Высыпь пыль из совка', 'Опустошить совок'],
    put_away: ['Верни инструмент на место', 'Убрать инструмент'],
  };
  const [instruction, button] = labels[state.nextStep] || ['Сохраняем результат…', 'Готово'];
  const roomNames = { living: 'гостиная', kitchen: 'кухня', bathroom: 'ванная' };
  dishUi.setAttribute('aria-label', state.title);
  dishEyebrow.textContent = `Работа по дому · ${roomNames[state.room] || state.room}`;
  dishInstruction.textContent = state.stage === 'awaiting_ack' ? 'Работа выполнена' : jobFeedback?.message || activeJobTask(state)?.hint || instruction;
  dishProgress.textContent = state.stage === 'awaiting_ack'
    ? 'Сохраняем результат…'
    : `Готово ${state.completed} из ${state.total}`;
  dishStepButton.textContent = button;
  dishStepButton.disabled = state.stage === 'awaiting_ack' ||
    (['J02', 'J04'].includes(state.jobId) && state.nextStep === 'sort');
  dishCancelButton.disabled = state.stage === 'awaiting_ack';
  if (renderer) renderer.render(scene, camera);
}

async function startJobGame(jobId, source = 'flutter_hud') {
  const definition = JOB_DEFINITIONS[jobId];
  let state = protocol.getState();
  if (!definition) return { ok: false, reason: 'unknown_job' };
  if (anyMinigameActive()) return { ok: false, reason: 'already_active' };
  if (state.mode !== 'home' || state.room !== definition.room) {
    return { ok: false, reason: 'wrong_room', requiredRoom: definition.room };
  }
  if (!state.jobsAllowed || state.jobPeriod < 1) return { ok: false, reason: 'job_locked' };
  if (state.busy || protocol.getPending()) return { ok: false, reason: 'busy' };
  await Promise.all([roomReadyPromise, petReadyPromise]);
  state = protocol.getState();
  if (!roomRoot || !petModel || currentRoomId !== definition.room || isRuntimePaused() || contextLost) {
    return { ok: false, reason: 'scene_loading' };
  }
  if (jobPropsJobId !== jobId) {
    await loadJobProps(roomDefinition(definition.room), jobId);
    state = protocol.getState();
    if (state.room !== definition.room || state.mode !== 'home' || jobPropsJobId !== jobId) {
      return { ok: false, reason: 'scene_loading' };
    }
  }
  resetJobPropVisuals();
  accessibleMinigameToken += 1;
  jobRound = createJobRound(jobId);
  jobPeriod = state.jobPeriod;
  jobCompletedSteps = [];
  jobPointer = null;
  jobTapSelection = null;
  jobFeedback = null;
  initializeJobInteractionState(jobId);
  jobRound.start();
  configureJobCamera(`job_${jobId.toLowerCase()}`);
  if (['J02', 'J04'].includes(jobId)) positionJobPetObserver(true);
  else void movePetTo(interactionPointFor(`job_${jobId.toLowerCase()}`, 'approach'), 460);
  updateJobView();
  refreshJobGuidance();
  emitJobProgress();
  diagnostic('HOUSEHOLD_JOB_STARTED', { jobId, source, jobPeriod });
  return { ok: true, game: 'household_job', jobId };
}

function cancelActiveJobPlacement(restore = true) {
  const run = activeJobPlacement;
  jobPlacementSerial += 1;
  activeJobPlacement = null;
  jobPlacementBusy = false;
  if (restore && run?.source?.parent) {
    run.source.position.copy(run.originPosition);
    run.source.quaternion.copy(run.originQuaternion);
    run.source.scale.copy(run.originScale);
    run.source.updateMatrixWorld(true);
  }
  return Boolean(run);
}

function animateJobPlacementSegment(run, target, duration, arcHeight, targetQuaternion) {
  const source = run.source;
  const start = source.position.clone();
  const startQuaternion = source.quaternion.clone();
  const effectiveDuration = protocol.getState().reducedMotion ? 0 : duration;
  if (effectiveDuration === 0) {
    source.position.copy(target);
    source.quaternion.copy(targetQuaternion);
    return Promise.resolve(true);
  }
  let elapsedMs = 0;
  let lastAt = null;
  return new Promise((resolve) => {
    const tick = (now) => {
      if (activeJobPlacement !== run || run.serial !== jobPlacementSerial || !source.parent) return resolve(false);
      if (isRuntimePaused()) {
        lastAt = null;
        requestAnimationFrame(tick);
        return;
      }
      if (lastAt === null) lastAt = now;
      elapsedMs += Math.max(0, now - lastAt);
      lastAt = now;
      const t = Math.min(1, elapsedMs / effectiveDuration);
      const eased = 1 - ((1 - t) ** 3);
      source.position.lerpVectors(start, target, eased);
      source.position.y += Math.sin(Math.PI * t) * arcHeight;
      source.quaternion.slerpQuaternions(startQuaternion, targetQuaternion, eased);
      source.updateMatrixWorld(true);
      if (t < 1) requestAnimationFrame(tick);
      else resolve(true);
    };
    requestAnimationFrame(tick);
  });
}

function placementMotion(task, source) {
  const destination = placementDestination(task);
  if (!destination) return [];
  if (J02_BOOK_SOURCES.has(task.source)) {
    const upright = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, Math.PI / 2, 0));
    return [
      { target: destination.clone().add(new THREE.Vector3(0, 0.025, 0.18)), duration: 180, arc: 0.07, quaternion: upright },
      { target: destination, duration: 220, arc: 0, quaternion: upright },
    ];
  }
  if (task.source === 'teddy_toy') {
    return [{ target: destination, duration: 320, arc: 0.07,
      quaternion: new THREE.Quaternion().setFromEuler(new THREE.Euler(0, THREE.MathUtils.degToRad(25), 0)) }];
  }
  return [{ target: destination, duration: 360, arc: 0.08,
    quaternion: new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, 0)) }];
}

async function placeJobItem(selection, gesture = null) {
  const state = jobRound?.getState();
  if (!state || state.stage !== 'active' || !['J02', 'J04'].includes(state.jobId) || state.nextStep !== 'sort') {
    return { ok: false, reason: 'wrong_stage', ...(state || {}) };
  }
  if (isRuntimePaused() || contextLost) return { ok: false, reason: 'paused', ...state };
  if (jobPlacementBusy) return { ok: false, reason: 'busy', ...state };
  const sourceId = typeof selection?.sourceId === 'string' ? selection.sourceId : '';
  const targetId = typeof selection?.targetId === 'string' ? selection.targetId : '';
  const knownSources = (JOB_TASKS[state.jobId] || []).map((task) => task.source);
  const knownTargets = placementTargetTasks(state.jobId).map((task) => task.targetId);
  if (!knownSources.includes(sourceId)) return { ok: false, reason: 'unknown_source', ...state };
  if (!remainingJobTasks(state).some((task) => task.source === sourceId)) {
    return { ok: false, reason: 'source_unavailable', ...state };
  }
  if (!knownTargets.includes(targetId)) return { ok: false, reason: 'unknown_target', ...state };
  if (jobOccupiedTargetIds.has(targetId)) return { ok: false, reason: 'target_occupied', ...state };
  const task = resolvedPlacementTask(state, sourceId, targetId);
  if (!task) {
    if (gesture) restoreJobGesture(gesture);
    emitJobFeedback('wrong_target', 'Это место не подходит — попробуй сравнить ещё раз');
    return { ok: false, reason: 'wrong_target', ...state };
  }
  const source = jobProps.get(sourceId);
  if (!source) return { ok: false, reason: 'missing_source', ...state };
  clearJobFeedback();
  const run = {
    serial: ++jobPlacementSerial,
    source,
    originPosition: gesture?.startPosition?.clone() || source.userData.jobInitial?.position?.clone() || source.position.clone(),
    originQuaternion: gesture?.startRotation
      ? new THREE.Quaternion().setFromEuler(gesture.startRotation)
      : source.userData.jobInitial?.rotation
        ? new THREE.Quaternion().setFromEuler(source.userData.jobInitial.rotation) : source.quaternion.clone(),
    originScale: gesture?.startScale?.clone() || source.userData.jobInitial?.scale?.clone() || source.scale.clone(),
  };
  activeJobPlacement = run;
  jobPlacementBusy = true;
  emitJobProgress(state);
  for (const segment of placementMotion(task, source)) {
    if (!await animateJobPlacementSegment(run, segment.target, segment.duration, segment.arc, segment.quaternion)) {
      if (activeJobPlacement === run) cancelActiveJobPlacement(true);
      const current = jobRound?.getState();
      if (current) emitJobProgress(current);
      return { ok: false, reason: 'cancelled', ...(current || state) };
    }
  }
  if (activeJobPlacement !== run || isRuntimePaused() || contextLost) {
    if (activeJobPlacement === run) cancelActiveJobPlacement(true);
    const current = jobRound?.getState();
    if (current) emitJobProgress(current);
    return { ok: false, reason: 'cancelled', ...(current || state) };
  }
  activeJobPlacement = null;
  jobPlacementBusy = false;
  const result = jobStep('sort', task);
  if (state.jobId === 'J02' && result.ok) void runtimeAudio.play('clothPlace');
  emitJobProgress(jobRound?.getState() || result);
  return result;
}

function jobStep(kind, task = activeJobTask()) {
  if (!jobRound) return { ok: false, reason: 'not_active' };
  if (isRuntimePaused() || contextLost) return { ok: false, reason: 'paused' };
  const stateBefore = jobRound.getState();
  const remaining = remainingJobTasks(stateBefore);
  const resolvedPlacement = task?.placementResolved === true && ['J02', 'J04'].includes(stateBefore.jobId) &&
    remaining.some((candidate) => candidate.source === task.source) &&
    resolvedPlacementTask(stateBefore, task.source, task.targetId)?.targetId === task.targetId;
  if (!task || task.kind !== kind || (!remaining.includes(task) && !resolvedPlacement)) {
    return { ok: false, reason: 'task_unavailable', ...stateBefore };
  }
  const result = jobRound.step(kind);
  if (!result.ok) return { ok: false, reason: 'wrong_stage', ...result };
  jobCompletedTaskIds.add(jobTaskKey(task));
  jobCompletedTaskOrder.push(task.source);
  if (kind === 'sort' && ['J02', 'J04'].includes(result.jobId)) jobOccupiedTargetIds.add(task.targetId);
  applyJobPropStep(result.jobId, kind, result.completed, task);
  if (result.jobId === 'J03' && kind === 'fold') void runtimeAudio.play('clothFold');
  if (result.jobId === 'J03' && kind === 'shelf') void runtimeAudio.play('clothPlace');
  jobCompletedSteps.push(kind);
  jobTapSelection = null;
  jobFeedback = null;
  updateJobView();
  if (!['wipe', 'sweep'].includes(kind) || result.stage !== 'active') {
    configureJobCamera(`job_${result.jobId.toLowerCase()}`);
  }
  refreshJobGuidance();
  if (result.stage !== 'ready') {
    emitJobProgress(result);
    return result;
  }
  const state = protocol.getState();
  const definition = JOB_DEFINITIONS[result.jobId];
  if (state.room !== definition.room || state.mode !== 'home' || state.jobPeriod !== jobPeriod) {
    cancelJobGame();
    return { ok: false, reason: 'state_changed' };
  }
  const started = protocol.beginAction({
    action: 'complete_job', jobId: result.jobId, room: definition.room, source: 'minigame',
  });
  if (!started.ok) {
    cancelJobGame();
    return started;
  }
  jobRound.markRequested();
  protocol.markRequested(started.action.id);
  updateJobView();
  emitJobProgress();
  postBridge({
    type: 'action', id: started.action.id, action: 'complete_job', room: definition.room,
    jobId: result.jobId, jobPeriod,
    proof: { completed: result.total, total: result.total, steps: [...jobCompletedSteps] },
  });
  return { ok: true, stage: 'awaiting_ack', id: started.action.id };
}

function cancelJobGame() {
  if (!jobRound) return { ok: true };
  const result = jobRound.cancel();
  if (!result.ok) return { ok: false, reason: 'awaiting_ack' };
  void runtimeAudio.play('uiBack');
  runtimeAudio.stopContact();
  accessibleMinigameToken += 1;
  cancelActiveJobPlacement(false);
  cancelActiveJobClothFold();
  resetJobClothSoil();
  resetJobPropVisuals();
  configureCamera(roomDefinition());
  jobRound = null;
  jobPeriod = 0;
  jobCompletedSteps = [];
  jobPointer = null;
  jobTapSelection = null;
  jobFeedback = null;
  jobCompletedTaskIds.clear();
  jobCompletedTaskOrder.length = 0;
  jobOccupiedTargetIds.clear();
  jobCoverageFields.clear();
  jobDustPiles.clear();
  jobDirtVisuals.clear();
  clearGroup(jobGuideLayer);
  clearGroup(jobEffectLayer);
  jobPanFillVisual = null;
  jobPanFillLevel = 0;
  jobPanEmptying = false;
  jobPanEmptyProgress = 0;
  j06BroomParkPending = false;
  dishUi.hidden = true;
  emitJobProgress(result);
  if (protocol.getState().mode === 'home') void movePetTo(petHome, 320);
  return { ok: true };
}

function minigameDelay(milliseconds, token) {
  return new Promise((resolve) => setTimeout(() => resolve(token === accessibleMinigameToken), milliseconds));
}

async function accessibleDishStepImpl(kind) {
  const stage = dishRound.getState().stage;
  if (kind !== (stage === 'water_off' ? 'finish' : stage)) return { ok: false, reason: 'wrong_stage', ...dishRound.getState() };
  const token = ++accessibleMinigameToken;
  const lowMotion = protocol.getState().reducedMotion;
  if (kind === 'scrub') {
    const patch = dishDirt.filter((entry) => !dishCleanedPatches.has(entry))
      .sort((a, b) => a.userData.coverage.coverage() - b.userData.coverage.coverage())[0];
    if (!patch || !dishSponge) return { ok: false, reason: 'no_remaining_stain' };
    const rows = [-0.02, -0.007, 0.007, 0.02];
    const firstContact = new THREE.Vector3(patch.position.x - 0.023, DISH_SPONGE_CONTACT_Y, patch.position.z + rows[0]);
    const motionEpoch = dishSpongeMotionEpoch;
    if (!await moveDishSpongeToContact(firstContact, lowMotion ? 50 : 150, motionEpoch) ||
        token !== accessibleMinigameToken) return { ok: false, reason: 'cancelled' };
    let previous = firstContact;
    for (let row = 0; row < rows.length && !dishCleanedPatches.has(patch); row += 1) {
      const direction = row % 2 === 0 ? 1 : -1;
      for (let item = row === 0 ? 1 : 0; item <= 6 && !dishCleanedPatches.has(patch); item += 1) {
        if (token !== accessibleMinigameToken || isRuntimePaused()) return { ok: false, reason: 'cancelled' };
        const x = patch.position.x + direction * (-0.023 + item * 0.0077);
        const point = new THREE.Vector3(x, DISH_SPONGE_CONTACT_Y, patch.position.z + rows[row]);
        if (!await animateDishSpongeContact(dishSponge, [previous.x, previous.z], [point.x, point.z],
          lowMotion ? 0 : 34, 0, motionEpoch) || token !== accessibleMinigameToken) {
          return { ok: false, reason: 'cancelled' };
        }
        sampleDishScrub(previous, point, lowMotion ? 1 / 30 : 1 / 60);
        previous = point;
        if (lowMotion && !await minigameDelay(18, token)) return { ok: false, reason: 'cancelled' };
      }
    }
    runtimeAudio.stopContact();
    dishFoam.breakStroke();
    return { ok: dishCleanedPatches.has(patch), ...dishRound.getState() };
  }
  if (kind === 'rinse') {
    const parked = dishSpongeParked ? true : await beginDishSpongeParking();
    if (!parked || token !== accessibleMinigameToken || isRuntimePaused() || contextLost) {
      return { ok: false, reason: 'cancelled' };
    }
    const ready = await dishRinseReady;
    if (!ready || token !== accessibleMinigameToken || dishRound.getState().stage !== 'rinse') {
      return { ok: false, reason: 'rinse_not_ready' };
    }
    const plate = jobProps.get('dish_plate');
    if (!plate) return { ok: false, reason: 'missing_plate' };
    const stream = new THREE.Vector3(DISH_WATER_NOZZLE[0], DISH_RINSE_SURFACE_Y, DISH_WATER_NOZZLE[2]);
    const grid = [-0.055, -0.037, -0.018, 0, 0.018, 0.037, 0.055];
    const offsets = grid.flatMap((z, row) => grid.map((x) => [row % 2 ? -x : x, z]));
    let totalClearing = 0;
    for (let index = 0; index < offsets.length * 4; index += 1) {
      if (token !== accessibleMinigameToken || isRuntimePaused()) return { ok: false, reason: 'cancelled' };
      if (dishRound.getState().stage !== 'rinse') return { ok: true, ...dishRound.getState() };
      const [x, z] = offsets[index % offsets.length];
      plate.position.set(DISH_PLATE_CANONICAL[0] + x, DISH_RINSE_PLATE_Y, DISH_PLATE_CANONICAL[2] + z);
      plate.updateMatrixWorld(true);
      dishPlate.position.set(plate.position.x, DISH_RINSE_SURFACE_Y, plate.position.z);
      dishFoam.setSurface({ center: dishPlate.position, normal: [0, 1, 0], radius: DISH_SURFACE_RADIUS });
      syncDishWater();
      const rinsed = dishFoam.rinseAt(stream, DISH_RINSE_INTENSITY, lowMotion ? 1 / 30 : 1 / 60);
      totalClearing += rinsed.clearing || 0;
      const foam = recordDishRinse(rinsed);
      const peak = Math.max(1, foam.foamPeak || foam.foamCount || 1);
      updateDishView();
      emitDishCoverageProgress();
      if (foam.foamCount / peak <= 1 - DISH_RINSE_THRESHOLD) break;
      if (!await minigameDelay(lowMotion ? 24 : 46, token)) return { ok: false, reason: 'cancelled' };
      dishFoam.update(lowMotion ? 0.04 : 0.055);
    }
    dishFoam.update(0.1);
    if (dishRound.getState().stage !== 'rinse') return { ok: true, ...dishRound.getState() };
    const remainingFoam = dishFoam.diagnostics();
    const remainingPeak = Math.max(1, remainingFoam.foamPeak || remainingFoam.foamCount || 1);
    if (remainingFoam.foamCount / remainingPeak > 1 - DISH_RINSE_THRESHOLD) {
      return { ok: false, reason: 'rinse_incomplete', foamCount: remainingFoam.foamCount,
        foamPeak: remainingPeak, rinseSamples: remainingFoam.rinseSamples, totalClearing, ...dishRound.getState() };
    }
    dishRinseProgress = 1;
    dishFoam.finishRinse();
    return dishStep('rinse');
  }
  return requestDishFinish();
}

function accessibleDishStep(kind) {
  // Keep the public control locked until the current physical motion finishes.
  // Coverage can advance before the final animation frame, so a second click
  // must not invalidate that motion's token and leave the next stain partial.
  if (dishAccessibleStepPending) return dishAccessibleStepPending;
  const run = accessibleDishStepImpl(kind);
  dishAccessibleStepPending = run;
  updateDishView();
  void run.then(() => {
    if (dishAccessibleStepPending === run) {
      dishAccessibleStepPending = null;
      updateDishView();
    }
  }, () => {
    if (dishAccessibleStepPending === run) {
      dishAccessibleStepPending = null;
      updateDishView();
    }
  });
  return run;
}

async function animateAccessibleJobClothFold(entry, token, lowMotion) {
  if (!entry) return false;
  const run = { entry, token };
  activeJobClothFold = run;
  const startProgress = jobClothFoldTotalProgress(entry);
  const frames = Math.max(1, Math.ceil((lowMotion ? 10 : 40) * (1 - startProgress)));
  for (let frame = 1; frame <= frames; frame += 1) {
    const state = jobRound?.getState();
    if (activeJobClothFold !== run || token !== accessibleMinigameToken || isRuntimePaused() || contextLost ||
        state?.stage !== 'active' || state.jobId !== 'J03') {
      if (activeJobClothFold === run) {
        entry.controller.reset();
        activeJobClothFold = null;
      }
      return false;
    }
    setJobClothFoldProgress(entry, THREE.MathUtils.lerp(startProgress, 1, frame / frames));
    if (frame < frames && !await minigameDelay(lowMotion ? 18 : 24, token)) {
      if (activeJobClothFold === run) {
        entry.controller.reset();
        activeJobClothFold = null;
      }
      return false;
    }
  }
  if (activeJobClothFold === run) activeJobClothFold = null;
  return true;
}

async function accessibleJobStep(kind = jobRound?.getState().nextStep, selectedTask = activeJobTask()) {
  const state = jobRound?.getState();
  if (!state || state.stage !== 'active' || !selectedTask || selectedTask.kind !== kind) {
    return { ok: false, reason: 'wrong_stage', ...(state || {}) };
  }
  if (kind === 'sort' && ['J02', 'J04'].includes(state.jobId)) {
    return { ok: false, reason: 'choice_required', ...state };
  }
  const token = ++accessibleMinigameToken;
  const lowMotion = protocol.getState().reducedMotion;
  const source = jobObjectForTask(selectedTask);
  if (!source) return { ok: false, reason: 'missing_source' };
  if (kind === 'fold') {
    const folded = await animateAccessibleJobClothFold(jobClothFolds.get(selectedTask.source), token, lowMotion);
    if (!folded) return { ok: false, reason: 'cancelled', ...jobRound.getState() };
    return jobStep(kind, selectedTask);
  }
  if (kind === 'wipe') {
    const center = vec3(selectedTask.target);
    const approachFrom = source.position.clone();
    const firstContact = new THREE.Vector3(center.x - 0.1, center.y, center.z - 0.07);
    const approachFrames = lowMotion ? 2 : 6;
    for (let frame = 1; frame <= approachFrames; frame += 1) {
      if (token !== accessibleMinigameToken || isRuntimePaused()) {
        source.position.copy(approachFrom);
        return { ok: false, reason: 'cancelled' };
      }
      source.position.lerpVectors(approachFrom, firstContact, frame / approachFrames);
      if (!await minigameDelay(lowMotion ? 12 : 24, token)) {
        source.position.copy(approachFrom);
        return { ok: false, reason: 'cancelled' };
      }
    }
    let previous = firstContact;
    for (const z of [-0.07, -0.035, 0, 0.035, 0.07]) {
      for (let item = 0; item <= 5; item += 1) {
        if (token !== accessibleMinigameToken || isRuntimePaused()) {
          source.position.copy(approachFrom);
          return { ok: false, reason: 'cancelled' };
        }
        const direction = Math.round((z + 0.07) / 0.035) % 2 === 0 ? 1 : -1;
        const point = new THREE.Vector3(center.x + direction * (-0.1 + item * 0.04), center.y, center.z + z);
        source.position.copy(point);
        sampleShelfWipe(previous, point);
        previous = point;
        if (!await minigameDelay(lowMotion ? 12 : 24, token)) {
          source.position.copy(approachFrom);
          return { ok: false, reason: 'cancelled' };
        }
      }
    }
    runtimeAudio.stopContact();
    return { ok: jobCompletedTaskIds.has(jobTaskKey(selectedTask)), ...jobRound.getState() };
  }
  if (kind === 'sweep') {
    const pile = jobDustPiles.get(selectedTask.targetId);
    if (!pile) return { ok: false, reason: 'missing_pile' };
    const firstDirection = pile.intake.clone().sub(pile.position).setY(0).normalize();
    const firstContact = pile.position.clone().addScaledVector(firstDirection, -0.07).setY(J06_FLOOR_Y);
    await animateJobProp(source, firstContact.toArray(), lowMotion ? 70 : 190, lowMotion ? 0 : 0.025);
    if (token !== accessibleMinigameToken || isRuntimePaused()) return { ok: false, reason: 'cancelled' };
    for (let stroke = 0; stroke < 12 && !pile.captured; stroke += 1) {
      if (token !== accessibleMinigameToken || isRuntimePaused()) return { ok: false, reason: 'cancelled' };
      const toward = pile.intake.clone().sub(pile.position).setY(0).normalize();
      const from = pile.position.clone().addScaledVector(toward, -0.07).setY(J06_FLOOR_Y);
      const to = pile.position.clone().addScaledVector(toward, 0.09).setY(J06_FLOOR_Y);
      source.position.copy(to);
      sampleFloorSweep(from, to, selectedTask);
      if (!await minigameDelay(lowMotion ? 18 : 42, token)) return { ok: false, reason: 'cancelled' };
    }
    runtimeAudio.stopContact();
    return { ok: pile.captured, ...jobRound.getState() };
  }
  const lift = source.position.clone();
  lift.y += 0.06;
  await animateJobProp(source, lift.toArray(), lowMotion ? 50 : 140);
  if (token !== accessibleMinigameToken || isRuntimePaused()) return { ok: false, reason: 'cancelled' };
  return jobStep(kind, selectedTask);
}

async function beginAction(action, targetRoom, source = 'runtime', guard = null) {
  if (!ACTIONS.has(action)) throw new ProtocolError('INVALID_ACTION', 'unknown action');
  cancelPetReaction('action');
  if (action === 'job_j01') action = 'wash_dishes';
  if (action === 'wash_dishes') {
    cancelNavigation();
    const result = await startDishGame(source);
    if (result.ok) void runtimeAudio.play('uiTap');
    return result;
  }
  const jobId = jobIdForAction(action);
  if (jobId) {
    cancelNavigation();
    const result = await startJobGame(jobId, source);
    if (result.ok) void runtimeAudio.play('uiTap');
    return result;
  }
  if (!guard) cancelNavigation();
  if (activeContact) return { ok: false, reason: 'contact_active' };
  if (anyMinigameActive()) return { ok: false, reason: 'minigame_active' };
  // A pause must not hide an action that still awaits the Flutter acknowledgement.
  const awaiting = protocol.getPending();
  if (awaiting) return { ok: false, reason: 'pending', pending: awaiting };
  if (isRuntimePaused() || contextLost || !readySent) return { ok: false, reason: 'not_ready' };
  const state = protocol.getState();
  if (state.mode === 'adoption') return { ok: false, reason: 'adoption_mode' };
  if (!ownsOptionalFixture(action, state)) return { ok: false, reason: 'not_owned' };
  const expectedPetKey = `${state.species}:${state.color}:${state.wearable || 'none'}`;
  if (!roomRoot || !petModel || currentRoomId !== effectiveRoom(state) || currentPetKey !== expectedPetKey) {
    return { ok: false, reason: 'scene_loading' };
  }
  if (action !== 'room') {
    const preferred = PREFERRED_ROOM[action];
    if (preferred && state.room !== preferred) {
      diagnostic('ACTION_UNAVAILABLE_IN_ROOM', { action, room: state.room, requiredRoom: preferred });
      return { ok: false, reason: 'wrong_room', requiredRoom: preferred };
    }
    const id = normalizeActionId(action, state);
    const hasActionTarget = actionDescriptor(id) || roomInteractives(roomDefinition()).some((entry) => bridgeAction(entry.id) === action);
    if (!hasActionTarget) {
      diagnostic('ACTION_ANCHOR_MISSING', { action, room: state.room, descriptorId: id });
      return { ok: false, reason: 'missing_anchor' };
    }
  } else if (targetRoom === state.room) {
    return { ok: false, reason: 'already_in_room' };
  } else if (!doorDescriptor(targetRoom)) {
    diagnostic('DOOR_UNAVAILABLE', { room: state.room, targetRoom });
    return { ok: false, reason: 'missing_door' };
  }
  const started = protocol.beginAction({ action, room: state.room, targetRoom, source });
  if (!started.ok) return started;
  void runtimeAudio.play('uiTap');
  const record = started.action;
  if (guard && navigation) navigation.inFlightId = record.id;
  try {
    if (action !== 'room') configureJobCamera(normalizeActionId(action, state));
    const fullApproach = interactionPointFor(action, 'approach', targetRoom);
    const approach = action === 'room' && !state.reducedMotion
      ? doorPreviewPoint(fullApproach) : fullApproach;
    approach.y = roomDefinition()?.floor?.height ?? 0;
    await movePetTo(approach, 560, guard ? 'navigation' : 'interaction');
    if (guard && !guard()) {
      protocol.resolveAction({ id: record.id, accepted: false, message: 'navigation cancelled' });
      return { ok: false, reason: 'cancelled' };
    }
    if (protocol.getState().room !== record.room) {
      protocol.resolveAction({ id: record.id, accepted: false, message: 'room changed before request' });
      diagnostic('ACTION_ABORTED_ROOM_CHANGED', { id: record.id, requestedRoom: record.room, room: protocol.getState().room });
      return { ok: false, reason: 'room_changed' };
    }
    if (action === 'room' && !state.reducedMotion) {
      const faded = await fadeRoomCurtain(1);
      if (!faded || isRuntimePaused() || contextLost || (guard && !guard())
          || protocol.getState().room !== record.room) {
        clearRoomCurtain();
        protocol.resolveAction({ id: record.id, accepted: false, message: 'room transition cancelled' });
        return { ok: false, reason: 'cancelled' };
      }
      roomCurtainActionId = record.id;
    }
    protocol.markRequested(record.id);
    postBridge({
      type: 'action',
      id: record.id,
      action: record.action,
      room: record.room,
      ...(record.targetRoom ? { targetRoom: record.targetRoom } : {}),
    });
    return { ok: true, id: record.id };
  } catch (error) {
    protocol.resolveAction({ id: record.id, accepted: false, message: 'approach failed' });
    reportError('ACTION_APPROACH_FAILED', error, true, { id: record.id, action });
    configureCamera(roomDefinition());
    await movePetTo(petHome, 280);
    return { ok: false, reason: 'approach_failed' };
  }
}

function requestAction(action, targetRoom) {
  try {
    if (action === 'room') return Promise.resolve(startNavigation(targetRoom));
    const pendingPromise = beginAction(action, targetRoom, 'flutter_hud');
    return pendingPromise;
  } catch (error) {
    reportError(error.code || 'INVALID_ACTION', error, true);
    return Promise.resolve({ ok: false, reason: error.code || 'invalid_action' });
  }
}

async function resolveAction(ack) {
  try {
    const result = protocol.resolveAction(ack);
    if (result.status === 'duplicate') {
      diagnostic('DUPLICATE_ACK_IGNORED', { id: ack?.id });
      return result;
    }
    if (result.status === 'unknown') {
      diagnostic('UNKNOWN_ACK_IGNORED', { id: ack?.id });
      return result;
    }
    const activeRoute = navigation?.inFlightId === result.action.id ? navigation : null;
    if (result.stateResult) await applyVisualState(result.stateResult.changed, result.stateResult.previous);
    if (result.action.action === 'wash_dishes') {
      if (result.status === 'accepted') {
        const finishingRound = dishRound;
        // A fast host receipt must not hide the placed plate before its result
        // is visible. The financial acknowledgement is already resolved.
        await dishResultPlacement;
        if (!running || dishRound !== finishingRound || dishRound.getState().stage !== 'awaiting_ack') return result;
        const remaining = Math.max(0, dishResultVisibleUntil - performance.now());
        if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, remaining));
        if (!running || dishRound !== finishingRound || dishRound.getState().stage !== 'awaiting_ack') return result;
      }
      dishRound.finish(result.status === 'accepted');
      if (result.status !== 'accepted') resetJobPropVisuals();
      runtimeAudio.stopContact();
      accessibleMinigameToken += 1;
      resetDishSurfaceState();
      dishRound = createDishRound();
      dishJobPeriod = 0;
      dishPointer = null;
      updateDishView();
      emitDishProgress();
      configureCamera(roomDefinition());
      if (protocol.getState().room === 'kitchen') void movePetTo(petHome, 320);
      return result;
    }
    if (result.action.action === 'complete_job') {
      const completedJobId = result.action.jobId || jobRound?.getState().jobId;
      jobRound?.finish(result.status === 'accepted');
      if (result.status !== 'accepted') {
        resetJobClothSoil();
        resetJobPropVisuals();
      }
      clearGroup(jobGuideLayer);
      clearGroup(jobEffectLayer);
      runtimeAudio.stopContact();
      accessibleMinigameToken += 1;
      cancelActiveJobPlacement(false);
      jobRound = null;
      jobPeriod = 0;
      jobCompletedSteps = [];
      jobPointer = null;
      jobTapSelection = null;
      jobFeedback = null;
      jobCompletedTaskIds.clear();
      jobCompletedTaskOrder.length = 0;
      jobOccupiedTargetIds.clear();
      jobCoverageFields.clear();
      jobDustPiles.clear();
      jobDirtVisuals.clear();
      jobPanFillVisual = null;
      jobPanFillLevel = 0;
      jobPanEmptying = false;
      jobPanEmptyProgress = 0;
      j06BroomParkPending = false;
      dishUi.hidden = true;
      if (completedJobId) emitJobProgress(createJobRound(completedJobId).getState());
      configureCamera(roomDefinition());
      if (protocol.getState().mode === 'home') void movePetTo(petHome, 320);
      return result;
    }
    if (isRuntimePaused() || contextLost) {
      // The frame loop is stopped, so a contact or walk would never finish.
      // Pausing already cancels running contacts; an ack under a covered route
      // likewise skips the visual and returns the pet to its place.
      if (petModel) {
        petLayer.position.copy(petHome);
        facePetToCamera();
      }
      diagnostic('ACTION_VISUAL_SKIPPED_PAUSED', { id: result.action.id, action: result.action.action, status: result.status });
      clearRoomCurtain();
      if (activeRoute && navigation === activeRoute) {
        activeRoute.inFlightId = null;
        cancelNavigation();
      }
      return result;
    }
    if (result.status === 'accepted') {
      await Promise.allSettled([roomReadyPromise, petReadyPromise]);
      await runContact(result.action);
      configureCamera(roomDefinition());
      if (result.action.action === 'room') {
        roomCurtainActionId = null;
        if (roomCurtain.visible) await fadeRoomCurtain(0);
      }
    } else {
      if (result.action.action === 'room') clearRoomCurtain();
      await movePetTo(petHome, 320);
      configureCamera(roomDefinition());
      diagnostic('ACTION_REJECTED', { id: result.action.id, action: result.action.action, message: result.message });
    }
    if (activeRoute && navigation === activeRoute) {
      activeRoute.inFlightId = null;
      if (result.status === 'accepted') await advanceNavigation(activeRoute.token);
      else cancelNavigation();
    } else if (navigation && !protocol.getPending()) {
      void advanceNavigation(navigation.token);
    }
    return result;
  } catch (error) {
    clearRoomCurtain();
    reportError(error.code || 'INVALID_ACK', error, true, { id: ack?.id });
    return { status: 'invalid' };
  }
}

function setState(patch) {
  try {
    const previousRoom = protocol.getState().room;
    const result = protocol.setState(patch);
    if (result.changed.some((key) => ['room', 'mode', 'species', 'color', 'wearable'].includes(key))) {
      cancelActiveContact('state_changed');
    }
    if (result.state.room !== previousRoom) {
      clearGuidance();
      const pending = protocol.getPending();
      const expectedRouteChange = navigation && (
        navigation.targetRoom === result.state.room ||
        (pending?.action === 'room' && pending.targetRoom === result.state.room)
      );
      if (navigation && !expectedRouteChange) cancelNavigation();
    }
    if (result.state.mode !== 'home' && navigation) cancelNavigation();
    const dish = dishRound.getState();
    if (dish.stage !== 'idle' && dish.stage !== 'awaiting_ack' &&
        (result.state.room !== 'kitchen' || result.state.mode !== 'home' ||
         !result.state.jobsAllowed || result.state.jobPeriod !== dishJobPeriod)) {
      cancelDishGame();
    }
    const job = jobRound?.getState();
    if (job && job.stage !== 'awaiting_ack' &&
        (result.state.room !== job.room || result.state.mode !== 'home' ||
         !result.state.jobsAllowed || result.state.jobPeriod !== jobPeriod)) {
      cancelJobGame();
    }
    void applyVisualState(result.changed, result.previous);
    return result.state;
  } catch (error) {
    reportError(error.code || 'INVALID_STATE', error, true);
    return protocol.getState();
  }
}

function dishHit(event, object) {
  if (!object) return false;
  updatePointerRay(event);
  return raycaster.intersectObject(object, false).length > 0;
}

function pointOnDishSurface(point) {
  if (!point || !dishPlate) return false;
  return Math.hypot(point.x - dishPlate.position.x, point.z - dishPlate.position.z) <= DISH_SURFACE_RADIUS;
}

function sampleDishScrub(from, to, deltaSeconds) {
  if (!pointOnDishSurface(to) || dishRound.getState().stage !== 'scrub') {
    dishFoam.breakStroke();
    return false;
  }
  const sampleFrom = pointOnDishSurface(from) ? from : to;
  let changed = false;
  let dirtColor = null;
  for (let index = 0; index < dishDirt.length; index += 1) {
    const patch = dishDirt[index];
    const field = dishCoverageFields[index];
    if (!field || dishCleanedPatches.has(patch)) continue;
    if (Math.hypot(to.x - patch.position.x, to.z - patch.position.z) <= field.radius + DISH_BRUSH_RADIUS) {
      dirtColor = patch.material?.color?.getHex?.() ?? dirtColor;
    }
    const normalize = (point) => ({
      x: (point.x - patch.position.x) / field.radius,
      y: (point.z - patch.position.z) / field.radius,
    });
    patch.userData.cleaningMask?.stroke(normalize(sampleFrom), normalize(to), DISH_BRUSH_RADIUS / field.radius);
    const before = field.coverage();
    const after = field.sampleSegment(sampleFrom, to, DISH_BRUSH_RADIUS);
    if (after > before) {
      changed = true;
      if (field.complete()) {
        patch.userData.cleaningMask?.stroke({ x: 0, y: 0 }, { x: 0, y: 0 }, 2);
        dishStep('scrub', patch);
      }
    }
  }
  const contact = to.clone().setY(DISH_SURFACE_Y + 0.012);
  dishFoam.scrubAt(contact, 1, deltaSeconds, dirtColor);
  runtimeAudio.contact('spongeScrub');
  updateDishView();
  if (changed) emitDishCoverageProgress();
  return changed;
}

function moveDishPlateUnderStream(event, gesture) {
  if (dishSpongeParkingActive || !dishSpongeParked || !dishRinsePlateReady) return false;
  const previous = gesture.lastContact?.clone() || gesture.source.position.clone();
  updatePointerRay(event);
  const hit = new THREE.Vector3();
  if (!raycaster.ray.intersectPlane(gesture.plane, hit)) return false;
  hit.x = THREE.MathUtils.clamp(hit.x, DISH_PLATE_CANONICAL[0] - DISH_RINSE_HALF_EXTENT,
    DISH_PLATE_CANONICAL[0] + DISH_RINSE_HALF_EXTENT);
  hit.z = THREE.MathUtils.clamp(hit.z, DISH_PLATE_CANONICAL[2] - DISH_RINSE_HALF_EXTENT,
    DISH_PLATE_CANONICAL[2] + DISH_RINSE_HALF_EXTENT);
  gesture.source.position.set(hit.x, DISH_RINSE_PLATE_Y, hit.z);
  gesture.source.updateMatrixWorld(true);
  dishPlate.position.set(hit.x, DISH_RINSE_SURFACE_Y, hit.z);
  dishFoam.setSurface({ center: dishPlate.position, normal: [0, 1, 0], radius: DISH_SURFACE_RADIUS });
  syncDishWater();
  const distance = previous.distanceTo(hit);
  gesture.lastContact = hit.clone();
  const stream = new THREE.Vector3(DISH_WATER_NOZZLE[0], DISH_RINSE_SURFACE_Y, DISH_WATER_NOZZLE[2]);
  if (!isDishSurfaceContact(hit, stream, DISH_SURFACE_RADIUS) || distance < 0.003) return false;
  const dt = Math.max(1 / 120, Math.min(0.08, (performance.now() - gesture.lastAt) / 1000));
  gesture.lastAt = performance.now();
  const rinsed = dishFoam.rinseAt(stream, DISH_RINSE_INTENSITY, dt);
  const foam = recordDishRinse(rinsed);
  const peak = Math.max(1, foam.foamPeak || foam.foamCount || 1);
  runtimeAudio.contact('waterFlow');
  updateDishView();
  emitDishCoverageProgress();
  if (dishRinseProgress >= DISH_RINSE_THRESHOLD && foam.rinseSamples >= 3 &&
      foam.foamCount / peak <= 1 - DISH_RINSE_THRESHOLD && dishRound.getState().stage === 'rinse') {
    dishStep('rinse');
  }
  return true;
}

function dishPointerDown(event) {
  const stage = dishRound.getState().stage;
  if (isRuntimePaused() || contextLost || !['scrub', 'rinse', 'water_off'].includes(stage)) return;
  if (stage === 'rinse' && (dishSpongeParkingActive || !dishSpongeParked || !dishRinsePlateReady)) {
    if (!dishSpongeParkingActive && !dishSpongeParked) void beginDishSpongeParking();
    emitDishFeedback('sponge_parking', 'Подожди, пока тарелка окажется под струёй');
    return;
  }
  const target = stage === 'water_off' ? dishTap : dishPlate;
  const source = stage === 'scrub' ? dishSponge : stage === 'rinse' ? jobProps.get('dish_plate') : target;
  const hit = stage === 'scrub' ? pointerHitsObject(event, source, 56)
    : stage === 'rinse' ? pointerHitsObject(event, source, 64) : dishHit(event, target);
  if (!hit) {
    emitDishFeedback('wrong_target', stage === 'scrub' ? 'Сначала возьми губку' : stage === 'rinse' ? 'Нажми на тарелку, чтобы смыть пену' : 'Нажми на кран');
    return;
  }
  if (stage === 'scrub') dishFoam.breakStroke();
  dishPointer = {
    id: event.pointerId, x: event.clientX, y: event.clientY, moved: false, stage,
    source, startPosition: source?.position?.clone(),
    startRotation: source?.rotation?.clone(), startScale: source?.scale?.clone(),
    startLogicalContact: stage === 'scrub' && dishSpongeLogicalContact ? [...dishSpongeLogicalContact] : null,
    plane: ['scrub', 'rinse'].includes(stage)
      ? new THREE.Plane(new THREE.Vector3(0, 1, 0), stage === 'rinse' ? -DISH_RINSE_PLATE_Y : -DISH_SPONGE_CONTACT_Y) : null,
    lastContact: stage === 'scrub' && dishSpongeLogicalContact
      ? new THREE.Vector3(dishSpongeLogicalContact[0], DISH_SPONGE_CONTACT_Y, dishSpongeLogicalContact[1])
      : source?.position?.clone(),
    lastAt: performance.now(),
  };
  canvas.setPointerCapture?.(event.pointerId);
}

function dishPointerMove(event) {
  if (!dishPointer || dishPointer.id !== event.pointerId || dishPointer.stage !== dishRound.getState().stage) return;
  const distance = Math.hypot(event.clientX - dishPointer.x, event.clientY - dishPointer.y);
  if (distance < 3) return;
  dishPointer.x = event.clientX;
  dishPointer.y = event.clientY;
  dishPointer.moved = true;
  const now = performance.now();
  if (dishPointer.stage === 'scrub' && dishPointer.source) {
    const previous = dishPointer.lastContact?.clone() || dishPointer.source.position.clone();
    const hit = moveJobSourceWithPointer(event, dishPointer);
    if (!hit) return;
    const physicalPose = dishSpongePointerPose(hit.x, hit.z);
    applyDishSpongePose(dishPointer.source, physicalPose);
    dishSpongeLogicalContact = physicalPose.onPlate ? [hit.x, hit.z] : null;
    dishSpongeParked = false;
    dishSpongeMotionPhase = physicalPose.onPlate ? 'pointer_contact' : 'pointer_offplate';
    if (renderer) renderer.render(scene, camera);
    const dt = Math.max(1 / 120, Math.min(0.08, (now - dishPointer.lastAt) / 1000));
    dishPointer.lastContact = hit.clone();
    dishPointer.lastAt = now;
    sampleDishScrub(previous, hit, dt);
  }
  if (dishPointer.stage === 'rinse') moveDishPlateUnderStream(event, dishPointer);
}

function dishPointerUp(event) {
  if (!dishPointer || dishPointer.id !== event.pointerId) return;
  const prior = dishPointer;
  dishPointer = null;
  if (prior.stage === 'scrub') dishFoam.breakStroke();
  if (prior.stage !== 'rinse') runtimeAudio.stopContact();
  if (isRuntimePaused() || contextLost || prior.stage !== dishRound.getState().stage) return;
  if (prior.stage === 'scrub' && !prior.moved) {
    restoreDishGesture(prior);
    emitDishFeedback('drag_required', 'Проведи губкой по отмеченному пятну');
  }
  if (prior.stage === 'water_off' && dishHit(event, dishTap)) void requestDishFinish();
}

function pointerHitsObject(event, object, radiusPx = 42) {
  if (!object) return false;
  updatePointerRay(event);
  return raycaster.intersectObject(object, true).length > 0 || eventDistanceToWorld(event, objectWorldCenter(object)) <= radiusPx;
}

function emitMovingJobProgress() {
  const now = performance.now();
  if (now - jobProgressEmitAt < 100) return;
  jobProgressEmitAt = now;
  emitJobProgress();
}

function sampleShelfWipe(from, to) {
  const state = jobRound?.getState();
  if (state?.jobId !== 'J05' || state.nextStep !== 'wipe') return false;
  let changed = false;
  for (const task of remainingJobTasks(state)) {
    const field = jobCoverageFields.get(task.targetId);
    if (!field) continue;
    const patch = jobDirtVisuals.get(task.targetId);
    const horizontal = task.surface === 'floor';
    const normalize = horizontal
      ? (point) => ({ x: (point.x - task.target[0]) / field.radius, y: (point.z - task.target[2]) / field.radius })
      : (point) => ({ x: (point.x - task.target[0]) / field.radius, y: -(point.y - task.target[1]) / field.radius });
    patch?.userData.cleaningMask?.stroke(normalize(from), normalize(to), 0.05 / field.radius);
    const before = field.coverage();
    const after = horizontal
      ? field.sampleSegment({ x: from.x, z: from.z }, { x: to.x, z: to.z }, 0.05)
      : field.sampleSegment({ x: from.x, z: from.y }, { x: to.x, z: to.y }, 0.05);
    if (after <= before) continue;
    changed = true;
    if (field.complete()) {
      patch?.userData.cleaningMask?.stroke({ x: 0, y: 0 }, { x: 0, y: 0 }, 2);
      jobStep('wipe', task);
    }
  }
  if (!changed) return false;
  updateJobClothSoil();
  runtimeAudio.contact('clothWipe');
  refreshJobGuidance();
  emitMovingJobProgress();
  return true;
}

function sampleFloorSweep(from, to, onlyTask = null) {
  const state = jobRound?.getState();
  if (state?.jobId !== 'J06' || state.nextStep !== 'sweep') return false;
  let moved = false;
  const candidates = onlyTask ? [onlyTask] : remainingJobTasks(state);
  for (const task of candidates) {
    if (!remainingJobTasks(state).includes(task)) continue;
    const pile = jobDustPiles.get(task.targetId);
    if (!pile || pile.captured) continue;
    const outcome = pushDustPile({
      position: pile.position, from, to, intake: pile.intake,
      contactRadius: 0.11, captureRadius: 0.1, requiredDirectionDot: 0.2,
      bounds: J06_WORK_BOUNDS,
    });
    if (!outcome.moved && !outcome.captured) continue;
    moved = true;
    const remaining = Math.hypot(pile.position.x - pile.intake.x, pile.position.z - pile.intake.z);
    pile.travel = Math.min(1, 1 - remaining / pile.initialDistance);
    updateJ06DebrisVisual(pile);
    updateJ06BroomPose(jobProps.get('short_broom'), from, to);
    if (outcome.captured && !pile.captured) {
      pile.captured = true;
      pile.travel = 1;
      updateJ06DebrisVisual(pile);
      jobStep('sweep', task);
    }
  }
  if (!moved) return false;
  runtimeAudio.contact('broomSweep');
  refreshJobGuidance();
  emitMovingJobProgress();
  return true;
}

function jobPointerDown(event) {
  if (!genericJobActive() || isRuntimePaused() || contextLost || activeJobClothFold || jobPlacementBusy) return;
  const state = jobRound.getState();
  const task = jobTapSelection?.task || taskAtPointer(event, state) || activeJobTask(state);
  const object = jobObjectForTask(task);
  if (!task || !object) return;
  if (task.kind === 'fold') {
    const foldEntry = jobClothFolds.get(task.source);
    const edges = jobClothFoldDragPoints(foldEntry);
    const distanceToEdge = edges.source
      ? Math.hypot(event.clientX - edges.source.x, event.clientY - edges.source.y) : Infinity;
    if (!foldEntry || !edges.source || !edges.valid || distanceToEdge > 72) {
      emitJobFeedback('fold_edge_required', 'Начни движение с отмеченного края полотенца');
      return;
    }
    clearJobFeedback();
    const fullDx = edges.valid.x - edges.fullSource.x;
    const fullDy = edges.valid.y - edges.fullSource.y;
    jobPointer = {
      id: event.pointerId, x: event.clientX, y: event.clientY,
      kind: task.kind, task, source: object, moved: false,
      startPosition: object.position.clone(), startScale: object.scale.clone(), startRotation: object.rotation.clone(),
      foldEntry, foldStartProgress: edges.progress,
      foldVector: { x: fullDx, y: fullDy }, foldProgress: edges.progress,
    };
    canvas.setPointerCapture?.(event.pointerId);
    return;
  }
  if (jobTapSelection && jobTapSelection.completed === state.completed) {
    jobPointer = {
      id: event.pointerId, x: event.clientX, y: event.clientY, moved: false,
      kind: task.kind, task, source: jobTapSelection.source,
      startPosition: jobTapSelection.startPosition, startScale: jobTapSelection.startScale,
      startRotation: jobTapSelection.startRotation, targetTap: true,
    };
    canvas.setPointerCapture?.(event.pointerId);
    return;
  }
  if (!pointerHitsObject(event, object, 52)) {
    emitJobFeedback('wrong_source', 'Сначала выбери отмеченный предмет');
    return;
  }
  clearJobFeedback();
  jobPointer = {
    id: event.pointerId, x: event.clientX, y: event.clientY,
    kind: state.nextStep, task, source: object, moved: false,
    startPosition: object.position.clone(), startScale: object.scale.clone(), startRotation: object.rotation.clone(),
    // A stored cloth may be on another shelf. Cleaning starts at its first
    // pointer contact on the working plane, never along a path from storage.
    lastContact: task.kind === 'wipe' ? null : object.position.clone(),
    lastAt: performance.now(), plane: jobWorkingPlane(task, object),
  };
  if (['sort', 'shelf'].includes(task.kind)) object.scale.multiplyScalar(1.04);
  canvas.setPointerCapture?.(event.pointerId);
}

function jobPointerMove(event) {
  if (!jobPointer || jobPointer.id !== event.pointerId || jobPointer.targetTap || jobPointer.task.mode === 'tap') return;
  if (jobPointer.kind === 'fold') {
    const { x: dx, y: dy } = jobPointer.foldVector;
    const lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1) return;
    const progress = THREE.MathUtils.clamp(
      jobPointer.foldStartProgress +
        ((event.clientX - jobPointer.x) * dx + (event.clientY - jobPointer.y) * dy) / lengthSquared,
      0, 1,
    );
    jobPointer.moved ||= progress > 0.01;
    jobPointer.foldProgress = progress;
    setJobClothFoldProgress(jobPointer.foldEntry, progress);
    emitMovingJobProgress();
    return;
  }
  if (Math.hypot(event.clientX - jobPointer.x, event.clientY - jobPointer.y) >= 28) {
    jobPointer.moved = true;
    const previous = jobPointer.lastContact?.clone();
    const hit = moveJobSourceWithPointer(event, jobPointer);
    if (!hit) return;
    jobPointer.lastContact = hit.clone();
    jobPointer.lastAt = performance.now();
    if (jobPointer.kind === 'wipe') sampleShelfWipe(previous || hit, hit);
    if (jobPointer.kind === 'sweep') sampleFloorSweep(previous || hit, hit);
  }
}

function jobPointerUp(event) {
  if (!jobPointer || jobPointer.id !== event.pointerId) return;
  const gesture = jobPointer;
  jobPointer = null;
  runtimeAudio.stopContact();
  if (j06BroomParkPending && gesture.source === jobProps.get('short_broom')) {
    void parkJ06Broom(!isRuntimePaused() && !contextLost).then((settled) => {
      if (settled && jobRound?.getState().jobId === 'J06') configureJobCamera('job_j06');
    });
  }
  if (isRuntimePaused() || contextLost || !genericJobActive()) return;
  const state = jobRound.getState();
  if (state.nextStep !== gesture.kind || state.completed !== (jobTapSelection?.completed ?? state.completed)) return;
  if (gesture.kind === 'fold') {
    if (gesture.foldProgress >= J03_FOLD_COMPLETE_THRESHOLD) {
      setJobClothFoldProgress(gesture.foldEntry, 1);
      clearJobFeedback();
      jobStep('fold', gesture.task);
    } else {
      gesture.foldEntry?.controller.reset();
      if (renderer) renderer.render(scene, camera);
      emitJobFeedback('fold_incomplete', 'Доведи край полотенца до противоположного края');
    }
    return;
  }
  const target = taskTargetPosition(gesture.task);
  if (gesture.targetTap) {
    if (gesture.kind === 'sort' && ['J02', 'J04'].includes(state.jobId)) {
      const chosen = placementTargetAtPointer(event, state, 76);
      jobTapSelection = null;
      if (chosen) {
        if (gesture.startScale) gesture.source.scale.copy(gesture.startScale);
        void placeJobItem({ sourceId: gesture.task.source, targetId: chosen.id }, gesture);
      } else {
        restoreJobGesture(gesture);
        emitJobFeedback('wrong_target', 'Выбери одно из видимых мест');
      }
      return;
    }
    if (target && pointerMatchesTaskTarget(event, state, gesture.task, 76)) {
      jobTapSelection = null;
      clearJobFeedback();
      if (gesture.startScale) gesture.source.scale.copy(gesture.startScale);
      void accessibleJobStep(gesture.kind, gesture.task);
    } else {
      jobTapSelection = null;
      restoreJobGesture(gesture);
      emitJobFeedback('wrong_target', 'Это не то место — предмет вернулся обратно');
    }
    return;
  }
  if (gesture.task.mode === 'tap') {
    if (pointerHitsObject(event, gesture.source, 58)) void accessibleJobStep(gesture.kind, gesture.task);
    else emitJobFeedback('wrong_target', 'Нажми прямо на полотенце');
    return;
  }
  if (!gesture.moved) {
    jobTapSelection = { task: gesture.task, source: gesture.source, startPosition: gesture.startPosition,
      startScale: gesture.startScale, startRotation: gesture.startRotation, completed: state.completed };
    emitJobFeedback('select_target', gesture.task.hint || 'Теперь нажми нужное место');
    return;
  }
  if (['wipe', 'sweep'].includes(gesture.kind)) return;
  if (gesture.kind === 'sort' && ['J02', 'J04'].includes(state.jobId)) {
    const chosen = placementTargetAtPointer(event, state, 82);
    if (chosen) {
      jobTapSelection = null;
      if (gesture.startScale) gesture.source.scale.copy(gesture.startScale);
      void placeJobItem({ sourceId: gesture.task.source, targetId: chosen.id }, gesture);
    } else {
      restoreJobGesture(gesture);
      emitJobFeedback('wrong_target', 'Не подошло — предмет вернулся обратно');
    }
    return;
  }
  if (target && pointerMatchesTaskTarget(event, state, gesture.task, 82)) {
    jobTapSelection = null;
    clearJobFeedback();
    if (gesture.startScale) gesture.source.scale.copy(gesture.startScale);
    jobStep(gesture.kind, gesture.task);
  } else {
    restoreJobGesture(gesture);
    emitJobFeedback('wrong_target', 'Не подошло — предмет вернулся обратно');
  }
}

function interactionFromPointer(event) {
  const state = protocol.getState();
  if (!renderer || paused || contextLost || state.mode === 'adoption' || state.busy || protocol.getPending() || anyMinigameActive()) return;
  const rect = canvas.getBoundingClientRect();
  pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  const hit = raycaster.intersectObjects(interactionMeshes, false)[0];
  if (!hit?.object?.userData?.interaction) {
    // Тап по самому питомцу: короткая счастливая реакция и голос вида.
    if (petModel && petLayer.visible && !activeContact
        && pointerHitsObject(event, petModel, 56)) {
      const reaction = playReaction({ kind: 'happy' });
      diagnostic('PET_TAP', { reaction: reaction?.ok !== false });
      if (reaction?.ok !== false) {
        void runtimeAudio.playPet(state.species);
      }
    }
    return;
  }
  const interaction = hit.object.userData.interaction;
  if (interaction.scenario) {
    void runPetScenario(interaction.scenario);
    return;
  }
  void beginAction(interaction.action, interaction.targetRoom, interaction.source || 'raycast');
}

function installPublicApi() {
  window.KopilychScene = Object.freeze({
    apiVersion: API_VERSION,
    setState,
    resolveAction,
    setPaused,
    setSoundEnabled,
    setSoundVolume,
    setGraphicsQuality,
    graphicsQualityDiagnostics,
    playAudioCue,
    disposeAudio,
    requestAction,
    showAction,
    dishStep: accessibleDishStep,
    cancelDishGame,
    jobStep: accessibleJobStep,
    cancelJobGame,
    placeJobItem,
    minigameInteractionDiagnostics,
    actionContactDiagnostics,
    lightingDiagnostics,
    runPetScenario,
    playReaction,
    setDialogueFraming,
    setPreviewFraming,
  });
}

async function initialize() {
  installPublicApi();
  setStatus('Готовим 3D-комнату…');
  try {
    createRenderer();
    descriptor = await loadDescriptor();
    const state = protocol.getState();
    roomReadyPromise = loadRoom(effectiveRoom(state));
    petReadyPromise = loadPet(state);
    if (state.mode === 'adoption' && descriptor.rooms.living?.adoption?.asset) {
      adoptionReadyPromise = loadAdoptionAsset(descriptor.rooms.living);
    }
    await Promise.all([roomReadyPromise, petReadyPromise, adoptionReadyPromise]);
    running = true;
    clock.start();
    scheduleFrame();
    maybeReady();
  } catch (error) {
    setStatus('Не удалось открыть 3D-комнату', 'error');
    reportError('RUNTIME_INIT_FAILED', error, false);
  }
}

canvas.addEventListener('pointerdown', dishPointerDown, { passive: true });
canvas.addEventListener('pointermove', dishPointerMove, { passive: true });
canvas.addEventListener('pointerup', dishPointerUp, { passive: true });
canvas.addEventListener('pointerdown', jobPointerDown, { passive: true });
canvas.addEventListener('pointermove', jobPointerMove, { passive: true });
canvas.addEventListener('pointerup', jobPointerUp, { passive: true });
canvas.addEventListener('pointercancel', () => {
  if (dishPointer) restoreDishGesture(dishPointer);
  if (jobPointer) restoreJobGesture(jobPointer);
  runtimeAudio.stopContact();
  dishFoam.breakStroke();
  dishPointer = null;
  jobPointer = null;
}, { passive: true });
canvas.addEventListener('pointerup', interactionFromPointer, { passive: true });
dishStepButton.addEventListener('click', () => {
  if (genericJobActive()) {
    const state = jobRound.getState();
    const next = state.nextStep;
    if (next === 'sort' && ['J02', 'J04'].includes(state.jobId)) return;
    if (next) void accessibleJobStep(next);
    return;
  }
  const stage = dishRound.getState().stage;
  if (stage === 'scrub') void accessibleDishStep('scrub');
  if (stage === 'rinse') void accessibleDishStep('rinse');
  if (stage === 'water_off') void accessibleDishStep('finish');
});
dishCancelButton.addEventListener('click', () => genericJobActive() ? cancelJobGame() : cancelDishGame());
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (genericJobActive()) cancelJobGame();
  else if (dishRound.getState().stage !== 'idle') cancelDishGame();
});
window.addEventListener('resize', resize, { passive: true });
window.visualViewport?.addEventListener('resize', resize, { passive: true });
const sceneSizeObserver = new ResizeObserver(() => resize());
sceneSizeObserver.observe(canvas);
function handleRuntimeVisibilityChange() {
  visibilityPaused = document.hidden;
  if (visibilityPaused) {
    qualityController.resetSamples();
    if (dishRound.getState().stage !== 'idle') pauseDishSpongeMotion();
    cancelActiveJobClothFold(false);
    if (dishPointer) restoreDishGesture(dishPointer);
    if (jobPointer?.kind !== 'fold') restoreJobGesture(jobPointer);
    dishPointer = null;
    jobPointer = null;
    runtimeAudio.stopContact();
    dishFoam.breakStroke();
    cancelActiveContact('hidden');
    cancelPetReaction('hidden');
  }
  if (!visibilityPaused && ['scrub', 'rinse'].includes(dishRound.getState().stage) &&
      !dishSpongeLogicalContact && !dishSpongeParked && !dishSpongeParkingActive) {
    void beginDishSpongeParking();
  }
  runtimeAudio.setPaused(isRuntimePaused() || contextLost);
  dishFoam.setPaused(isRuntimePaused() || contextLost);
  dishWater?.setPaused(isRuntimePaused() || contextLost);
  if (running) updatePauseLoop();
  if (!isRuntimePaused()) recoverDishRinseAfterInterruption();
}
document.addEventListener('visibilitychange', handleRuntimeVisibilityChange);

canvas.addEventListener('webglcontextlost', (event) => {
  event.preventDefault();
  contextLost = true;
  qualityController.resetSamples();
  accessibleMinigameToken += 1;
  cancelActiveJobPlacement(true);
  cancelActiveJobClothFold();
  resetJobClothFolds();
  if (jobPointer) restoreJobGesture(jobPointer);
  if (dishPointer) restoreDishGesture(dishPointer);
  jobPointer = null;
  dishPointer = null;
  runtimeAudio.stopContact();
  dishFoam.breakStroke();
  cancelNavigation();
  cancelActiveContact('context_lost');
  cancelPetReaction('context_lost');
  runtimeAudio.setPaused(true);
  dishFoam.setPaused(true);
  dishWater?.setPaused(true);
  if (frameHandle) cancelAnimationFrame(frameHandle);
  frameHandle = 0;
  if (activeTween) activeTween.lastAt = null;
  const releasedResources = releaseContextResources();
  setStatus('Восстанавливаем комнату…');
  diagnostic('WEBGL_CONTEXT_LOST', { room: protocol.getState().room, releasedResources });
});

canvas.addEventListener('webglcontextrestored', () => {
  contextLost = false;
  runtimeAudio.setPaused(isRuntimePaused());
  dishFoam.setPaused(isRuntimePaused());
  dishWater?.setPaused(isRuntimePaused());
  syncDishWater();
  lastFrameAt = 0;
  resize();
  diagnostic('WEBGL_CONTEXT_RESTORED', { room: protocol.getState().room });
  // WebGL restoration does not change the game state. Fabricating mode/room
  // changes here would cancel the partial minigame we have just restored.
  void applyVisualState().finally(() => {
    if (!running) return;
    maybeReady();
    if (!isRuntimePaused()) {
      recoverDishRinseAfterInterruption();
      scheduleFrame();
    }
  });
});

window.addEventListener('error', (event) => {
  reportError('UNCAUGHT_ERROR', event.error || event.message, true);
});

window.addEventListener('unhandledrejection', (event) => {
  reportError('UNHANDLED_REJECTION', event.reason, true);
});

window.addEventListener('pagehide', () => {
  running = false;
  if (frameHandle) cancelAnimationFrame(frameHandle);
  frameHandle = 0;
  document.removeEventListener('visibilitychange', handleRuntimeVisibilityChange);
  window.removeEventListener('resize', resize);
  window.visualViewport?.removeEventListener('resize', resize);
  sceneSizeObserver.disconnect();
  cancelActiveContact('pagehide');
  cancelPetReaction('pagehide');
  cancelActiveJobPlacement(false);
  disposeJobClothFolds();
  dishFoam.dispose();
  dishWater?.dispose();
  dishWater = null;
  void runtimeAudio.dispose();
}, { once: true });

void initialize();

