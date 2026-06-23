// Generate PNG slides for a carousel via Puppeteer.
// Usage: node generate.js <carousel-name>

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');
const {
  OUTPUT_DIR,
  buildFontCSS,
  loadCarousel,
  renderSlideHtml,
} = require('./_render-core');

async function generateCarousel(carouselName) {
  const { slides, config, templateHtml } = loadCarousel(carouselName);

  console.log('Loading fonts...');
  const fontCSS = buildFontCSS();

  const outputDir = path.join(OUTPUT_DIR, carouselName);
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });

  const width = config.width || 1080;
  const height = config.height || 1350;

  const browser = await puppeteer.launch({ headless: true });
  const page = await browser.newPage();
  await page.setViewport({ width, height, deviceScaleFactor: 1 });

  console.log('Rendering slides...');
  for (let i = 0; i < slides.length; i++) {
    const html = renderSlideHtml(templateHtml, slides[i], i, slides.length, config, fontCSS);
    await page.setContent(html, { waitUntil: 'domcontentloaded' });
    await new Promise(r => setTimeout(r, 200));

    const outputPath = path.join(outputDir, `slide-${String(i + 1).padStart(2, '0')}.png`);
    await page.screenshot({ path: outputPath, type: 'png' });
    console.log(`✓ Slide ${i + 1}/${slides.length}: ${outputPath}`);
  }

  await browser.close();
  console.log(`\nDone! ${slides.length} slides saved to: ${outputDir}`);
}

const carouselName = process.argv[2];
if (!carouselName) {
  console.log('Usage: node generate.js <carousel-name>');
  console.log('Example: node generate.js example');
  process.exit(1);
}

generateCarousel(carouselName).catch(err => {
  console.error(err);
  process.exit(1);
});
