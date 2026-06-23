// Build a browser-preview HTML gallery for a carousel (no Puppeteer, no PNGs).
// Used to show the creator what the carousel looks like before final PNG render.
// Usage: node preview.js <carousel-name>

const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const {
  OUTPUT_DIR,
  buildFontCSS,
  loadCarousel,
  renderSlideHtml,
} = require('./_render-core');

function generatePreview(carouselName) {
  const { slides, config, templateHtml } = loadCarousel(carouselName);

  const fontCSS = buildFontCSS();
  const width = config.width || 1080;
  const height = config.height || 1350;
  const scale = 0.4;

  const slideHtmls = slides.map((slide, i) =>
    renderSlideHtml(templateHtml, slide, i, slides.length, config, fontCSS)
  );

  const outputDir = path.join(OUTPUT_DIR, `preview-${carouselName}`);
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });

  slideHtmls.forEach((html, i) => {
    fs.writeFileSync(path.join(outputDir, `slide-${String(i + 1).padStart(2, '0')}.html`), html, 'utf-8');
  });

  const galleryHtml = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Preview: ${carouselName}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #111; font-family: system-ui, sans-serif; color: #fff; padding: 20px; }
  .header { text-align: center; padding: 10px 0 20px; }
  .header h1 { font-size: 20px; opacity: 0.7; }
  .header p { font-size: 13px; opacity: 0.4; margin-top: 4px; }
  .grid { display: flex; flex-wrap: wrap; gap: 16px; justify-content: center; }
  .slide-container {
    position: relative;
    width: ${Math.round(width * scale)}px;
    height: ${Math.round(height * scale)}px;
    overflow: hidden; border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.1);
    cursor: pointer; transition: border-color 0.2s;
  }
  .slide-container:hover { border-color: rgba(94,234,212,0.4); }
  .slide-container iframe {
    width: ${width}px; height: ${height}px; border: none;
    transform: scale(${scale}); transform-origin: top left; pointer-events: none;
  }
  .slide-label {
    position: absolute; bottom: 8px; left: 50%; transform: translateX(-50%);
    font-size: 11px; opacity: 0.4; font-weight: 600;
    background: rgba(0,0,0,0.6); padding: 2px 10px; border-radius: 4px; z-index: 10;
  }
  .overlay {
    display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.95);
    z-index: 100; justify-content: center; align-items: center; cursor: pointer;
  }
  .overlay.active { display: flex; }
  .overlay iframe { border: none; max-height: 95vh; max-width: 95vw; }
  .overlay-nav {
    position: fixed; top: 50%; transform: translateY(-50%);
    font-size: 40px; color: #fff; opacity: 0.3; cursor: pointer;
    z-index: 101; padding: 20px; user-select: none;
  }
  .overlay-nav:hover { opacity: 0.8; }
  .overlay-nav.prev { left: 10px; }
  .overlay-nav.next { right: 10px; }
  .overlay-close {
    position: fixed; top: 15px; right: 20px; font-size: 28px;
    color: #fff; opacity: 0.4; cursor: pointer; z-index: 101;
  }
  .overlay-close:hover { opacity: 1; }
  .overlay-counter {
    position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
    font-size: 14px; opacity: 0.4; z-index: 101;
  }
</style>
</head>
<body>
  <div class="header">
    <h1>${carouselName}</h1>
    <p>${slides.length} slides &middot; ${width}&times;${height} &middot; Click to enlarge</p>
  </div>
  <div class="grid">
    ${slideHtmls.map((_, i) => `
    <div class="slide-container" onclick="openSlide(${i})">
      <iframe id="thumb-${i}" srcdoc=""></iframe>
      <div class="slide-label">${i + 1} / ${slides.length}</div>
    </div>`).join('')}
  </div>

  <div class="overlay" id="overlay" onclick="closeOverlay(event)">
    <div class="overlay-close" onclick="closeOverlay()">&times;</div>
    <div class="overlay-nav prev" onclick="event.stopPropagation(); navSlide(-1)">&lsaquo;</div>
    <div class="overlay-nav next" onclick="event.stopPropagation(); navSlide(1)">&rsaquo;</div>
    <iframe id="overlay-frame" width="${width}" height="${height}"></iframe>
    <div class="overlay-counter" id="overlay-counter"></div>
  </div>

  <script>
    const slides = ${JSON.stringify(slideHtmls)};
    let currentSlide = 0;
    slides.forEach((html, i) => { document.getElementById('thumb-' + i).srcdoc = html; });

    function openSlide(i) {
      currentSlide = i;
      const overlay = document.getElementById('overlay');
      const frame = document.getElementById('overlay-frame');
      const vw = window.innerWidth * 0.9;
      const vh = window.innerHeight * 0.9;
      const s = Math.min(vw / ${width}, vh / ${height});
      frame.style.width = '${width}px';
      frame.style.height = '${height}px';
      frame.style.transform = 'scale(' + s + ')';
      frame.style.transformOrigin = 'center center';
      frame.srcdoc = slides[i];
      document.getElementById('overlay-counter').textContent = (i + 1) + ' / ' + slides.length;
      overlay.classList.add('active');
    }
    function closeOverlay(e) {
      if (e && e.target !== document.getElementById('overlay')) return;
      document.getElementById('overlay').classList.remove('active');
    }
    function navSlide(dir) {
      currentSlide = (currentSlide + dir + slides.length) % slides.length;
      openSlide(currentSlide);
    }
    document.addEventListener('keydown', (e) => {
      if (!document.getElementById('overlay').classList.contains('active')) return;
      if (e.key === 'Escape') document.getElementById('overlay').classList.remove('active');
      if (e.key === 'ArrowRight') navSlide(1);
      if (e.key === 'ArrowLeft') navSlide(-1);
    });
  </script>
</body>
</html>`;

  const galleryPath = path.join(OUTPUT_DIR, `preview-${carouselName}.html`);
  fs.writeFileSync(galleryPath, galleryHtml, 'utf-8');
  console.log(`Preview saved: ${galleryPath}`);
  console.log(`Individual slides: ${outputDir}/`);

  const cmd = process.platform === 'win32' ? 'start' : process.platform === 'darwin' ? 'open' : 'xdg-open';
  exec(`${cmd} "" "${galleryPath}"`);
  console.log('Opened in browser.');
}

const carouselName = process.argv[2];
if (!carouselName) {
  console.log('Usage: node preview.js <carousel-name>');
  process.exit(1);
}

generatePreview(carouselName);
