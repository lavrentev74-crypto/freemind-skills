// Shared rendering core — used by both generate.js (PNG) and preview.js (HTML gallery).
//
// Fonts live in ./fonts/ and are declared in ./fonts.config.json:
//   [
//     { "family": "Inter", "weight": "400 700", "file": "Inter-Variable.ttf" },
//     { "family": "Montserrat", "weight": 700, "file": "Montserrat-Bold.ttf" }
//   ]
// If fonts.config.json is missing, rendering still works with system/fallback fonts.

const fs = require('fs');
const path = require('path');

const LOCAL_FONTS = path.join(__dirname, 'fonts');
const ASSETS_DIR = path.join(__dirname, 'assets');
const TEMPLATES_DIR = path.join(__dirname, 'templates');
const CAROUSELS_DIR = path.join(__dirname, 'carousels');
const OUTPUT_DIR = path.join(__dirname, 'output');
const FONT_CONFIG = path.join(__dirname, 'fonts.config.json');

function loadFontFaces() {
  if (!fs.existsSync(FONT_CONFIG)) return [];
  try {
    const raw = fs.readFileSync(FONT_CONFIG, 'utf-8');
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      console.warn('  ⚠ fonts.config.json must be an array of font entries');
      return [];
    }
    return parsed;
  } catch (e) {
    console.warn(`  ⚠ Could not parse fonts.config.json: ${e.message}`);
    return [];
  }
}

function buildFontCSS() {
  const faces = loadFontFaces();
  let css = '';
  for (const f of faces) {
    if (!f || !f.file || !f.family) continue;
    const filepath = path.join(LOCAL_FONTS, f.file);
    if (!fs.existsSync(filepath)) {
      console.warn(`  ⚠ Font not found: ${f.file}`);
      continue;
    }
    const buf = fs.readFileSync(filepath);
    const b64 = buf.toString('base64');
    const ext = path.extname(f.file).slice(1).toLowerCase();
    const format = ext === 'ttf' ? 'truetype' : ext === 'otf' ? 'opentype' : ext === 'woff2' ? 'woff2' : ext === 'woff' ? 'woff' : ext;
    const weight = f.weight !== undefined ? f.weight : 400;
    css += `@font-face {
  font-family: '${f.family}';
  font-weight: ${weight};
  src: url(data:font/${format};base64,${b64}) format('${format}');
}\n`;
  }
  return css;
}

const assetCache = {};
function assetToDataURI(filename) {
  if (assetCache[filename]) return assetCache[filename];
  const filepath = path.join(ASSETS_DIR, filename);
  if (!fs.existsSync(filepath)) {
    console.warn(`  ⚠ Asset not found: ${filename}`);
    return '';
  }
  const buf = fs.readFileSync(filepath);
  const ext = path.extname(filename).slice(1).toLowerCase();
  const mimeMap = { svg: 'image/svg+xml', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp' };
  const mime = mimeMap[ext] || 'application/octet-stream';

  let dataURI;
  if (ext === 'svg') {
    dataURI = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(buf.toString('utf-8'))}`;
  } else {
    dataURI = `data:${mime};base64,${buf.toString('base64')}`;
  }
  assetCache[filename] = dataURI;
  return dataURI;
}

function resolveAssets(html) {
  return html.replace(/\{\{asset:([^}]+)\}\}/g, (_, filename) => assetToDataURI(filename.trim()));
}

// Load carousel data.json + template html. Returns { slides, config, templateHtml }.
function loadCarousel(carouselName) {
  const carouselDir = path.join(CAROUSELS_DIR, carouselName);
  const dataPath = path.join(carouselDir, 'data.json');
  const customTemplate = path.join(carouselDir, 'template.html');

  if (!fs.existsSync(dataPath)) {
    throw new Error(`Not found: ${dataPath}`);
  }

  const data = JSON.parse(fs.readFileSync(dataPath, 'utf-8'));
  const slides = data.slides;
  const config = data.config || {};

  let templateHtml;
  if (fs.existsSync(customTemplate)) {
    templateHtml = fs.readFileSync(customTemplate, 'utf-8');
  } else {
    const defaultTemplate = config.template || 'simple';
    templateHtml = fs.readFileSync(path.join(TEMPLATES_DIR, `${defaultTemplate}.html`), 'utf-8');
  }
  return { slides, config, templateHtml };
}

// Render a single slide — takes raw template + slide data + global config,
// returns fully-resolved HTML (fonts, placeholders, assets all inlined).
function renderSlideHtml(templateHtml, slide, index, totalSlides, config, fontCSS) {
  let html = templateHtml.replace('/* {{FONTS}} */', fontCSS);

  for (const [key, value] of Object.entries(slide)) {
    if (typeof value === 'string') {
      html = html.replaceAll(`{{${key}}}`, value);
    } else if (Array.isArray(value)) {
      const listHtml = value.map(item => `<li>${item}</li>`).join('\n');
      html = html.replaceAll(`{{${key}}}`, listHtml);
    }
  }

  html = html.replaceAll('{{slideNumber}}', String(index + 1));
  html = html.replaceAll('{{totalSlides}}', String(totalSlides));

  for (const [key, value] of Object.entries(config)) {
    if (typeof value === 'string') {
      html = html.replaceAll(`{{config.${key}}}`, value);
    }
  }

  html = resolveAssets(html);
  html = html.replace(/\{\{[^}]+\}\}/g, ''); // strip unused placeholders
  return html;
}

module.exports = {
  LOCAL_FONTS,
  ASSETS_DIR,
  TEMPLATES_DIR,
  CAROUSELS_DIR,
  OUTPUT_DIR,
  buildFontCSS,
  assetToDataURI,
  resolveAssets,
  loadCarousel,
  renderSlideHtml,
};
