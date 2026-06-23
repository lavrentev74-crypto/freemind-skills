---
name: carousel-generator
description: Generate Instagram/LinkedIn image carousels (PNG slides) locally via HTML templates and Puppeteer. No paid services needed. Use when the user asks to create, make, or generate a carousel — triggers include "создай карусель", "сделай карусель", "новая карусель", "карусель про X", "make a carousel", "create carousel". Pipeline: write data.json → preview HTML for review → render final PNGs.
---

# Carousel Generator

Generates branded image carousels (1080×1350 by default) from structured content + HTML templates. Runs fully locally via Puppeteer — no subscriptions, no external APIs.

## First run: personalize the starter

If the user just installed this skill and has not yet set up their brand, help them personalize the starter before generating any real carousel:

1. Read `BRAND.md` (if it exists) for the user's brand rules. If it doesn't exist, read `BRAND.example.md` and offer to create `BRAND.md` together by asking the user about: brand colors (primary, accent, text, background), fonts, tone of voice, visual style (minimal / bold / playful / editorial / etc.).
2. Read `templates/simple.html` — the default starter template. Offer to adapt it to the user's brand (colors, fonts, decoration style).
3. Read `fonts.config.json` and help the user register their fonts (download files to `./fonts/`, add entries to `fonts.config.json`).

Once `BRAND.md` exists, treat it as the source of truth for all subsequent carousels.

## Pipeline (every carousel)

1. **Read brand rules.** `BRAND.md` (user's brand) — colors, fonts, voice, do/don'ts. Never invent brand rules.
2. **Study the template.** Read the template HTML in `templates/` that the carousel will use. Know every available CSS class before writing `body`/`decor` HTML.
3. **Vary from previous carousels.** List `carousels/` and study the most recent data.json. New carousel must differ in slide count (5–8), cover variant, decorative assets, and layout. Copying last carousel's structure defeats the point.
4. **Write content.** Create `carousels/<slug>/data.json` where slug is kebab-case and descriptive (`ai-prompts-101`, not `carousel-1`).
5. **Preview.** Run `node preview.js <slug>` — opens an HTML gallery in the browser. The user reviews and gives corrections.
6. **Iterate.** Edit `data.json`, re-run preview, collect more feedback. Repeat until approved.
7. **Final render.** Only after explicit approval, run `node generate.js <slug>` → PNGs in `output/<slug>/slide-NN.png`.
8. **Show result.** Read 2–3 representative PNGs back to the user to confirm visual correctness.

**Never skip preview.** The preview is how issues get caught before PNG rendering.

**Never run `generate.js` before the user approves the preview.**

## data.json structure

```json
{
  "config": {
    "template": "simple",
    "cta": "→",
    "width": 1080,
    "height": 1350
  },
  "slides": [
    { "decor": "<optional decorative HTML>", "body": "<slide content HTML>" }
  ]
}
```

- **`config.template`** — filename in `templates/` (without `.html`). Default is `simple`. Advanced users have their own.
- **`config.cta`** — CTA shown in the footer area. Common: `"→"`, `"Swipe"`, `"Смотри описание ↓"`.
- **`body`** — main content using CSS classes from the chosen template.
- **`decor`** — absolutely-positioned floating assets (optional, often empty on text-heavy slides).
- **Assets** are referenced as `{{asset:filename.svg}}` — the renderer inlines them as data URIs.
- **Placeholders** `{{slideNumber}}` and `{{totalSlides}}` are substituted automatically.

Study `carousels/example/data.json` for the minimum working pattern, or any prior carousel in `carousels/` for more advanced patterns.

## Fonts

Fonts are declared in `fonts.config.json` at the project root:

```json
[
  { "family": "Inter", "weight": "400 700", "file": "Inter-Variable.ttf" },
  { "family": "Montserrat", "weight": 700, "file": "Montserrat-Bold.ttf" }
]
```

Font files go in `./fonts/`. The renderer inlines them as base64 — Puppeteer can't read system fonts, so every font must live in this folder.

If `fonts.config.json` is missing or empty, the template falls back to system fonts (Inter / system-ui). The carousel will still render.

## Assets

Any SVG/PNG/JPG in `./assets/` can be referenced from slides as `{{asset:filename.ext}}`. When the user asks for specific icons, check what's in `./assets/` first — if missing, ask the user to add them (or suggest downloading from a free library like Heroicons, Feather, Lucide, or Phosphor).

## Output

Final PNGs land in `output/<slug>/slide-01.png` … `slide-NN.png`. Report the folder path to the user; they handle posting to Instagram/LinkedIn manually.

## Failure modes to avoid

- Generating `data.json` before reading `BRAND.md` and the target template → wrong classes, off-brand design
- Running `generate.js` before preview approval → wastes render time on unreviewed content
- Copying the previous carousel's structure 1:1 → all carousels look identical, defeats the point
- Inventing CSS classes not defined in the template → slides render broken
- Referencing `{{asset:x.svg}}` when `assets/x.svg` doesn't exist → missing visuals
- Forgetting `config.template` → falls back to default, which may not match the user's brand

## Tech notes

- **First-time setup:** `npm install` then `npx puppeteer browsers install chrome` (Puppeteer needs a local Chromium).
- **Custom per-carousel template:** if a carousel needs its own layout, put `template.html` inside `carousels/<slug>/` — it takes precedence over `templates/<name>.html`.
- **Dimensions:** default 1080×1350 (Instagram/LinkedIn 4:5). Override via `config.width` / `config.height`.
