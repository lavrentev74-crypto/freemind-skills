# BRAND.md (example)

This file defines your brand rules for the carousel generator. Copy this file to `BRAND.md` and fill in your own values. Claude Code reads `BRAND.md` before every carousel to stay on-brand.

You don't have to fill everything perfectly on day one. Start with what you know, iterate as you generate carousels and refine the rules.

---

## Brand name

Your brand / account name. Appears in footers, covers, optionally.

Example: `Acme Studio`

## Positioning (one sentence)

What you do, for whom.

Example: `Design systems for early-stage SaaS founders.`

## Tone of voice

Three adjectives + one banned register.

Example: `Direct, practical, confident. No corporate jargon, no hype words.`

## Audience

Who reads your carousels.

Example: `Technical founders (0–2 year old startups), mostly US/EU, English-speaking.`

---

## Color palette

### Primary
| Role | Hex | When to use |
|------|-----|-------------|
| Background | `#fafafa` | Main slide background |
| Ink | `#1a1a1a` | Body text, titles |
| Accent | `#0066ff` | Highlights, CTAs, links |
| Muted | `#6b6b6b` | Secondary text, captions |

### Allowed accents (max 2 extra)
Example: `#ff5a1f` (warm) for emphasis, `#00b37a` (green) for positive data.

### Banned
Colors that violate the brand. Example: `No red. No pastels. No gradients unless explicitly requested.`

---

## Typography

### Headings
Font + weight + use.

Example: `Inter ExtraBold (800) for titles. Tight letter-spacing (-1px).`

### Body
Example: `Inter Regular (400) for body. 1.45 line-height.`

### Special
Example: `Display font for hero slides only — JetBrains Mono Bold for numbers/stats.`

### Rules
- Example: `Never mix more than 2 type families per carousel.`
- Example: `Titles always uppercase. Body always sentence case.`

---

## Visual style

### Layout
Example: `Generous whitespace. Content never fills more than 75% of the slide. No crowded text.`

### Decoration
Example: `Minimal. Occasional thin geometric lines. No photos. No 3D renders.`

### Icons
Example: `Monoline, 2px stroke. Lucide or Feather library only. Icons always match ink color, never colored.`

### Backgrounds
Example: `Solid or very subtle (2% noise). No gradients.`

---

## Content rules

### Slide count
Example: `5–8 slides per carousel. Hook + 3–5 content + CTA.`

### Slide structure
- **Slide 1 (hook):** Bold statement, stops the scroll.
- **Slide 2 (context):** Why the reader should care.
- **Slides 3–N (content):** One idea per slide. Clear hierarchy.
- **Last slide (CTA):** Follow / save / comment. One clear ask.

### Copy rules
- Example: `One idea per slide. No run-on sentences.`
- Example: `Use contractions in body copy ("you'll", "we're"). Not in titles.`
- Example: `Numbers over adjectives. "Cut 4 hours/week" beats "Save a lot of time".`

### Banned phrases
Example: `"Dive in", "Unlock", "Game-changer", "Seamless", "Robust", "Comprehensive".`

---

## Do's and don'ts

### Do
- Vary slide layout between carousels. Don't reuse the same cover style twice in a row.
- Study the last 2–3 carousels in `carousels/` before creating a new one.
- Keep hierarchy obvious: one dominant title, one supporting line, max.

### Don't
- Don't copy-paste the previous carousel and just swap the text.
- Don't use emojis in titles.
- Don't use em-dashes (`—`) in body copy. Use `. ` or `: ` instead.
- Don't invent CSS classes that aren't in the template.
