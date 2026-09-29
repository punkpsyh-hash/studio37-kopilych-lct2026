/** Local wipe trace for an existing stain mesh, not a replacement prop.
 * Points use -1..1 relative to the stain radius, with canvas Y pointing down.
 * Horizontal XZ surface: y = +z/r. Vertical XY surface: y = -y/r.
 */
export function createCleaningMask(THREE, { size = 128, appearance = 'solid', seed = 1 } = {}) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const context = canvas.getContext('2d');
  if (!context) throw new Error('Cleaning masks require a 2D canvas');
  const texture = new THREE.CanvasTexture(canvas);
  texture.generateMipmaps = false;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  let disposed = false;

  // The pattern belongs to the dirt, not to a replacement surface. Keep it
  // deterministic so retries restore the same mess and rotation never redraws it.
  let pattern = null;
  if (['sauce', 'porridge', 'crumbs', 'dust'].includes(appearance)) {
    pattern = context.createImageData(size, size);
    let randomState = (seed >>> 0) || 1;
    const random = () => {
      randomState = (Math.imul(randomState, 1664525) + 1013904223) >>> 0;
      return randomState / 4294967296;
    };
    const crumbs = Array.from({ length: 26 }, () => {
      const angle = random() * Math.PI * 2;
      const radius = Math.sqrt(random()) * 0.74;
      return { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius,
        radius: 0.025 + random() * 0.085 };
    });
    const phase = random() * Math.PI * 2;
    const smooth = (value) => { const t = Math.max(0, Math.min(1, value)); return t * t * (3 - 2 * t); };
    for (let row = 0; row < size; row += 1) {
      for (let column = 0; column < size; column += 1) {
        const x = (column + 0.5) * 2 / size - 1;
        const y = (row + 0.5) * 2 / size - 1;
        const angle = Math.atan2(y, x);
        const grain = random();
        let coverage;
        if (appearance === 'crumbs') {
          coverage = 0;
          for (const crumb of crumbs) coverage = Math.max(coverage,
            smooth((crumb.radius - Math.hypot(x - crumb.x, y - crumb.y)) / 0.025));
        } else if (appearance === 'dust') {
          const edge = Math.min(1 - Math.abs(x), 1 - Math.abs(y));
          coverage = smooth((edge - 0.04 + Math.sin(x * 17 + phase) * 0.025) / 0.24)
            * (0.56 + grain * 0.32 + Math.sin(x * 27 + y * 11) * 0.09);
        } else {
          const radius = Math.hypot(x / (appearance === 'sauce' ? 0.92 : 0.88), y / 0.8);
          const boundary = 0.84 + Math.sin(angle * 5 + phase) * 0.07
            + Math.cos(angle * 9 - phase) * 0.035;
          coverage = smooth((boundary - radius) / (appearance === 'sauce' ? 0.11 : 0.07));
          coverage *= appearance === 'sauce' ? 0.86 + grain * 0.14 : 0.60 + grain * 0.40;
        }
        const value = Math.round(Math.max(0, Math.min(1, coverage)) * 255);
        const index = (row * size + column) * 4;
        pattern.data[index] = pattern.data[index + 1] = pattern.data[index + 2] = value;
        pattern.data[index + 3] = 255;
      }
    }
  }

  function reset() {
    if (disposed) return;
    if (pattern) context.putImageData(pattern, 0, 0);
    else {
      context.fillStyle = '#fff';
      context.fillRect(0, 0, size, size);
    }
    texture.needsUpdate = true;
  }

  function stroke(from, to, brushRadius) {
    if (disposed || !from || !to || ![from.x, from.y, to.x, to.y, brushRadius].every(Number.isFinite)
        || brushRadius <= 0) return false;
    if (Math.max(from.x, to.x) + brushRadius < -1 || Math.min(from.x, to.x) - brushRadius > 1
        || Math.max(from.y, to.y) + brushRadius < -1 || Math.min(from.y, to.y) - brushRadius > 1) return false;
    const x1 = (from.x + 1) * size / 2;
    const y1 = (from.y + 1) * size / 2;
    const x2 = (to.x + 1) * size / 2;
    const y2 = (to.y + 1) * size / 2;
    // Alpha maps use their green channel, so black removes dirt. Canvas
    // antialiasing keeps the edge soft without a separate blur pass.
    context.strokeStyle = '#000';
    context.fillStyle = '#000';
    context.lineWidth = brushRadius * size;
    context.lineCap = 'round';
    context.beginPath();
    context.moveTo(x1, y1);
    context.lineTo(x2, y2);
    context.stroke();
    // A stationary initial contact still has a round footprint.
    context.beginPath();
    context.arc(x2, y2, brushRadius * size / 2, 0, Math.PI * 2);
    context.fill();
    texture.needsUpdate = true;
    return true;
  }

  reset();
  return Object.freeze({
    texture, stroke, reset,
    dispose() {
      if (disposed) return;
      disposed = true;
      texture.dispose();
      canvas.width = canvas.height = 1;
    },
  });
}
