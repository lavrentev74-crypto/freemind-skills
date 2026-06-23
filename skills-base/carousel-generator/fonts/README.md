# Fonts

Put your font files (`.ttf`, `.otf`, `.woff`, `.woff2`) here and register them in `../fonts.config.json`.

Example:

```json
[
  { "family": "Inter", "weight": "400 700", "file": "Inter-Variable.ttf" },
  { "family": "Montserrat", "weight": 700, "file": "Montserrat-Bold.ttf" }
]
```

## Why local files?

Puppeteer renders slides in a headless browser that can't read your system-installed fonts. Every font used in templates must be stored here as a file so the renderer can embed it as base64.

## Where to get fonts

- **Google Fonts** — https://fonts.google.com/ (click "Download family")
- **Open Foundry** — https://open-foundry.com/
- **Velvetyne** — https://velvetyne.fr/
- **Your paid license** — just drop the file here

## Free fallback

If this folder is empty and `fonts.config.json` has `[]`, the template falls back to system fonts (`system-ui`, `-apple-system`, `Inter` if installed in browser). Carousels will still render, just with generic typography.
