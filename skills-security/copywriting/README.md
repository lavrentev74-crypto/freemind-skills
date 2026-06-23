# Copywriting Skill

A comprehensive copywriting skill for Claude Code that writes marketing copy and automatically removes AI patterns.

## What's inside

```
copywriting/
├── SKILL.md                  # Main skill file
├── README.md                 # This file
└── references/
    ├── copy-frameworks.md    # Headline formulas, page section types, templates
    └── natural-transitions.md # Transition phrases, AI writing tells to avoid
```

## What it does

- Writes conversion-focused marketing copy for any page type
- Follows proven copywriting principles (clarity, benefits, specificity)
- Includes headline formulas with real-world examples
- Has page structure templates (landing page, feature page, pricing, etc.)
- **Built-in humanizer pass**: 19-point checklist that removes AI vocabulary, fixes patterns, and makes text sound natural

## Installation

Copy the entire `copywriting/` folder to `~/.claude/skills/`:

```
~/.claude/skills/
└── copywriting/
    ├── SKILL.md
    └── references/
        ├── copy-frameworks.md
        └── natural-transitions.md
```

## Usage

The skill triggers automatically when you ask Claude Code to write text:
- "Write hero section copy for my SaaS landing page"
- "Create a pricing page for my product"
- "Write an about page for my agency"
- "Rewrite this section to be more compelling"

## Key features

### Copywriting principles
- Clarity over cleverness
- Benefits over features
- Specificity over vagueness
- Customer language over company language

### Humanizer pass (auto-applied)
After writing any copy, the skill runs a mandatory checklist:
- Removes AI vocabulary (delve, leverage, robust, comprehensive...)
- Fixes em dashes, bold overuse, emoji pollution
- Removes chatbot artifacts ("I hope this helps", "Certainly!")
- Adds natural variation in sentence length and structure

### Reference files
- **copy-frameworks.md**: 20+ headline formulas, 15+ section types, 5 page templates
- **natural-transitions.md**: 100+ transition phrases organized by purpose, plus AI-tell phrases to avoid
