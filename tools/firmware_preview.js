// Browser-only bridge. Firmware algorithms run in the same native C++ library
// used by Flutter. All input in this design preview is explicitly synthetic.
const previewClient = 'design-' + crypto.randomUUID();
let nativeKey = '', nativeGeneration = 0, nativeFrames = [], nativePending = false;
let nativeLast = null, nativeFailure = false;
const pixelCanvas = document.createElement('canvas');
pixelCanvas.width = pixelCanvas.height = 16;
const pixelContext = pixelCanvas.getContext('2d');
const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
function nativeSettings(id = effect, bright = brightness) {
  return [id, bright, speed, ...rgb(color1), ...rgb(color2), gradient];
}
function paintNative(canvas, bytes) {
  if (!canvas || !bytes) return;
  pixelContext.putImageData(new ImageData(new Uint8ClampedArray(bytes), 16, 16), 0, 0);
  const rect=canvas.getBoundingClientRect(),ratio=Math.min(3,devicePixelRatio||1);
  const thumb=canvas.hasAttribute('data-thumb');
  const width=Math.max(1,Math.round((thumb?rect.width:Math.max(rect.width,rect.height))*ratio));
  const height=thumb?Math.max(1,Math.round(rect.height*ratio)):width;
  if(canvas.width!==width||canvas.height!==height){canvas.width=width;canvas.height=height;}
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  if(thumb){
    ctx.fillStyle='#07090d';ctx.fillRect(0,0,width,height);
    const cover=Math.max(width,height)*1.12,contain=Math.min(width,height);
    ctx.globalAlpha=.7;ctx.filter='blur('+(18*ratio)+'px)';
    ctx.drawImage(pixelCanvas,(width-cover)/2,(height-cover)/2,cover,cover);
    ctx.globalAlpha=1;ctx.globalCompositeOperation='screen';
    ctx.filter='blur('+(Math.max(5,rect.height/16*.9)*ratio)+'px)';
    ctx.drawImage(pixelCanvas,(width-contain)/2,(height-contain)/2,contain,contain);
    ctx.filter='none';ctx.globalCompositeOperation='source-over';
    return;
  }
  ctx.drawImage(pixelCanvas, 0, 0, canvas.width, canvas.height);
}
async function getNativeFrames(session, settings, count) {
  const response = await fetch('http://127.0.0.1:49469/frames', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session, settings, count }), signal: AbortSignal.timeout(5000)
  });
  if (!response.ok) throw new Error('Firmware renderer unavailable: ' + response.status);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length !== count * 1024) throw new Error('Incomplete firmware frames');
  return Array.from({ length: count }, (_, i) => bytes.slice(i * 1024, (i + 1) * 1024));
}
function presentMain() {
  paintNative($('#matrix'), nativeLast);
  paintNative($('#matrix-bloom'), nativeLast);
}
function requestFrames() {
  if (nativePending || nativeFailure) return;
  nativePending = true;
  const generation = nativeGeneration;
  getNativeFrames(previewClient + '-main', nativeSettings(), 60).then(frames => {
    if (generation !== nativeGeneration) return;
    nativeFrames.push(...frames);
    if (!nativeLast) nativeLast = nativeFrames.shift();
    presentMain();
    document.querySelector('#renderer-error')?.remove();
  }).catch(error => {
    if (generation !== nativeGeneration) return;
    nativeFailure = true;
    const card = $('.led-card');
    if (card && !$('#renderer-error')) {
      const note = document.createElement('p');
      note.id = 'renderer-error'; note.className = 'tiny';
      note.textContent = 'Preview renderer is unavailable. Controls remain usable.';
      card.after(note);
    }
    console.error(error);
  }).finally(() => {
    if (generation !== nativeGeneration) return;
    nativePending = false;
  });
}
function drawMain() {
  if (!$('#matrix')) return;
  const key = JSON.stringify(nativeSettings());
  if (key !== nativeKey) {
    nativeKey = key; nativeGeneration++;
    nativeFrames = []; nativePending = false; nativeFailure = false;
    // Do not display the previous effect or brightness while awaiting new frames.
    nativeLast = new Uint8Array(1024);
    for (let i = 3; i < nativeLast.length; i += 4) nativeLast[i] = 255;
    presentMain(); nativeLast = null;
    requestFrames();
  } else {
    presentMain();
    if (nativeFrames.length < 20) requestFrames();
  }
}
const thumbFrames = new Map();
async function drawThumbnails() {
  const canvases = [...content.querySelectorAll('[data-thumb]')];
  // Sequential native calls retain firmware RNG ordering and bound memory.
  for (const canvas of canvases) {
    const id = Number(canvas.dataset.thumb), key = JSON.stringify(nativeSettings(id, 100));
    try {
      if (!thumbFrames.has(key)) {
        const frames = await getNativeFrames(previewClient + '-thumb-' + id, nativeSettings(id, 100), 45);
        // Pick an actual energetic source frame rather than a dark beat interval.
        let best=frames[0],energy=-1;
        for(const frame of frames){
          let score=0;for(let i=0;i<frame.length;i+=4)score+=frame[i]+frame[i+1]+frame[i+2];
          if(score>energy){energy=score;best=frame;}
        }
        thumbFrames.set(key, best);
      }
      if (canvas.isConnected) paintNative(canvas, thumbFrames.get(key));
    } catch (error) { console.error(error); break; }
  }
}
function tick(time) {
  if (time - lastTick >= 1000 / 30) {
    lastTick = time;
    if (playing && !document.hidden &&
        (screen === 'light' || screen === 'ambient')) {
      drawMain();
      if (nativeFrames.length) { nativeLast = nativeFrames.shift(); presentMain(); }
    }
  }
  requestAnimationFrame(tick);
}
