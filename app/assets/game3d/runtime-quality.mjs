// Quality policy for the existing 30 FPS WebGL runtime. The host supplies hints
// and calls recordRenderedFrame only after a frame was actually rendered.
export const QUALITY_MODES = Object.freeze(['auto', 'low', 'standard', 'high']);

export const QUALITY_PROFILES = Object.freeze({
  low: Object.freeze({ dprCap: 1.25, anisotropy: 2, textureTier: 'low' }),
  standard: Object.freeze({ dprCap: 1.75, anisotropy: 4, textureTier: 'standard' }),
  high: Object.freeze({ dprCap: 2, anisotropy: 8, textureTier: 'high' }),
});

const TIERS = ['low', 'standard', 'high'];
const TEXTURE_LIMITS = Object.freeze({ low: 512, standard: 1024, high: Infinity });
const originalImages = new WeakMap();

function imageSize(image) {
  const width = image?.videoWidth || image?.naturalWidth || image?.width;
  const height = image?.videoHeight || image?.naturalHeight || image?.height;
  return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0
    ? { width, height } : null;
}

function sceneTextures(root) {
  const textures = new Set();
  root?.traverse?.((object) => {
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    for (const material of materials) {
      if (!material) continue;
      for (const value of Object.values(material)) if (value?.isTexture) textures.add(value);
    }
  });
  return textures;
}

export function initialQualityTier(hints = {}) {
  const { deviceMemory, hardwareConcurrency, maxTextureSize, webglVersion } = hints;
  // Browser device hints may be missing, rounded, or deliberately reduced.
  if ((deviceMemory > 0 && deviceMemory <= 2)
      || (hardwareConcurrency > 0 && hardwareConcurrency <= 4)
      || (maxTextureSize > 0 && maxTextureSize <= 4096)) return 'low';
  if (deviceMemory >= 6 && hardwareConcurrency >= 8
      && maxTextureSize >= 8192 && webglVersion >= 2) return 'high';
  return 'standard';
}

export function createRuntimeQualityController({ mode = 'auto', hints = {} } = {}) {
  if (!QUALITY_MODES.includes(mode)) throw new RangeError(`Unknown quality mode: ${mode}`);
  const initialTier = initialQualityTier(hints);
  let selectedMode = mode;
  let tier = mode === 'auto' ? initialTier : mode;
  let lastFrameAt = null;
  let windowStart = null;
  let renderedFrames = 0;
  let slowWindows = 0;
  let fastWindows = 0;
  let changedAt = -Infinity;

  function resetSamples() {
    lastFrameAt = null;
    windowStart = null;
    renderedFrames = slowWindows = fastWindows = 0;
  }

  function setMode(nextMode) {
    if (!QUALITY_MODES.includes(nextMode)) throw new RangeError(`Unknown quality mode: ${nextMode}`);
    selectedMode = nextMode;
    tier = nextMode === 'auto' ? initialTier : nextMode;
    changedAt = -Infinity;
    resetSamples();
    return getState();
  }

  function getState() {
    return { mode: selectedMode, tier, profile: QUALITY_PROFILES[tier] };
  }

  function recordRenderedFrame(now, { active = true } = {}) {
    if (!active) {
      resetSamples();
      return null;
    }
    if (selectedMode !== 'auto' || !Number.isFinite(now)) return null;
    if (lastFrameAt === null || now <= lastFrameAt || now - lastFrameAt > 250) {
      resetSamples();
      lastFrameAt = windowStart = now;
      return null;
    }
    lastFrameAt = now;
    renderedFrames += 1;
    const elapsed = now - windowStart;
    if (elapsed < 8000) return null;
    const fps = renderedFrames * 1000 / elapsed;
    // Too few samples cannot establish a stable sustained frame rate.
    if (renderedFrames < 100) {
      resetSamples();
      return null;
    }
    slowWindows = fps < 25 ? slowWindows + 1 : 0;
    fastWindows = fps >= 28.5 ? fastWindows + 1 : 0;
    renderedFrames = 0;
    windowStart = now;
    if (now - changedAt < 20000) return null;
    const step = slowWindows >= 2 ? -1 : fastWindows >= 3 ? 1 : 0;
    const nextTier = TIERS[Math.max(0, Math.min(TIERS.length - 1, TIERS.indexOf(tier) + step))];
    if (!step || nextTier === tier) return null;
    tier = nextTier;
    changedAt = now;
    slowWindows = fastWindows = 0;
    return getState();
  }

  return { getState, setMode, recordRenderedFrame, resetSamples };
}

export function applyRendererQuality(renderer, profile, { devicePixelRatio = 1, width, height } = {}) {
  if (!renderer || !profile) return;
  renderer.setPixelRatio(Math.min(Math.max(devicePixelRatio || 1, 1), profile.dprCap));
  if (Number.isFinite(width) && Number.isFinite(height)) {
    renderer.setSize(Math.max(1, width), Math.max(1, height), false);
  }
}

export function applyTextureFiltering(root, renderer, profile) {
  if (!root || !renderer || !profile) return;
  const max = renderer.capabilities?.getMaxAnisotropy?.() || 1;
  const target = Math.min(profile.anisotropy, max);
  for (const texture of sceneTextures(root)) {
    if (texture.anisotropy === target) continue;
    texture.anisotropy = target;
    texture.needsUpdate = true;
  }
}

// Replaces only decoded runtime image data. Source GLBs/PNGs and UVs stay intact;
// keeping the original image permits an immediate return to High without a reload.
export function applyTextureResolution(root, profile, { createCanvas } = {}) {
  const limit = TEXTURE_LIMITS[profile?.textureTier];
  if (!root || limit === undefined) return textureResolutionDiagnostics(root);
  const canvasFactory = createCanvas || ((width, height) => {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    return canvas;
  });
  const textures = sceneTextures(root);
  const changedSources = new Set();
  for (const texture of textures) {
    const source = texture.source;
    const current = source?.data;
    if (!source || !imageSize(current) || current.data || texture.isCompressedTexture ||
        texture.isVideoTexture || texture.isCanvasTexture ||
        (!originalImages.has(source) && typeof HTMLCanvasElement !== 'undefined' && current instanceof HTMLCanvasElement)) continue;
    if (!originalImages.has(source)) originalImages.set(source, current);
    const original = originalImages.get(source);
    const dimensions = imageSize(original);
    if (!dimensions) continue;
    const scale = Math.min(1, limit / Math.max(dimensions.width, dimensions.height));
    const width = Math.max(1, Math.round(dimensions.width * scale));
    const height = Math.max(1, Math.round(dimensions.height * scale));
    if (imageSize(current)?.width === width && imageSize(current)?.height === height) continue;
    if (scale === 1) {
      source.data = original;
    } else {
      const canvas = canvasFactory(width, height);
      const context = canvas.getContext?.('2d');
      if (!context) continue;
      context.drawImage(original, 0, 0, width, height);
      source.data = canvas;
    }
    changedSources.add(source);
  }
  for (const texture of textures) if (changedSources.has(texture.source)) texture.needsUpdate = true;
  return textureResolutionDiagnostics(root);
}

export function textureResolutionDiagnostics(root) {
  const sources = new Set();
  let originalPixels = 0;
  let activePixels = 0;
  for (const texture of sceneTextures(root)) {
    const source = texture.source;
    if (!source || sources.has(source)) continue;
    sources.add(source);
    const current = imageSize(source.data);
    const original = imageSize(originalImages.get(source) || source.data);
    if (current && original) {
      activePixels += current.width * current.height;
      originalPixels += original.width * original.height;
    }
  }
  return { textureCount: sources.size, originalPixels, activePixels };
}
