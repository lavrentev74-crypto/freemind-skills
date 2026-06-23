# PDF Generator Skill

A multi-skill pipeline for creating professional PDF documents with Claude Code.

## What's inside

```
pdf-generator/
├── SKILL.md                          # Main orchestrator skill
├── README.md                         # This file
└── skills/
    ├── copywriting/
    │   ├── SKILL.md                  # Copywriting skill (used in Phase 2-3)
    │   └── references/
    │       ├── copy-frameworks.md    # Headline formulas, page templates
    │       └── natural-transitions.md # Transition phrases, AI-tells to avoid
    └── pdf/
        ├── SKILL.md                  # PDF processing skill (used in Phase 4)
        ├── forms.md                  # PDF form filling guide
        └── reference.md             # Advanced PDF features
```

## How it works

The orchestrator runs 5 phases in sequence:

1. **Brief** - Clarify document type, topic, audience, branding
2. **Content** - Write text using the copywriting skill
3. **Humanize** - Remove AI patterns using the humanizer checklist
4. **Design + Build** - Generate the PDF using reportlab/pypdf
5. **Self-check** - Verify quality before delivering

## Installation

1. Copy the entire `pdf-generator/` folder to `~/.claude/skills/`
2. Copy the `skills/copywriting/` folder to `~/.claude/skills/copywriting/`
3. Enable the `pdf` plugin in Claude Code settings (or copy `skills/pdf/` to `~/.claude/skills/pdf/`)

Your final structure should look like:
```
~/.claude/skills/
├── pdf-generator/
│   └── SKILL.md
├── copywriting/
│   ├── SKILL.md
│   └── references/
│       ├── copy-frameworks.md
│       └── natural-transitions.md
└── pdf/
    ├── SKILL.md
    ├── forms.md
    └── reference.md
```

## Usage

Just ask Claude Code to create a PDF:
- "Create a checklist PDF for onboarding new employees"
- "Make a one-pager about our product"
- "Generate a guide on email marketing best practices"

The skill triggers automatically and runs the full pipeline.

## Document types supported

- **Checklist** - Single/multi-page with checkbox items
- **One-pager** - Dense single page with clear sections
- **Guide** - Cover + content pages + CTA
- **Report** - Cover + TOC + content + summary
