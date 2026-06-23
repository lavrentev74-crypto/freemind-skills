---
name: pdf-generator
description: |
  Create professional PDF documents (checklists, one-pagers, guides, reports).
  Orchestrates a multi-skill pipeline: design + copywriting + humanizer + self-check.
  Use when user asks to create a PDF document, downloadable guide, checklist, one-pager,
  or any branded PDF content. Triggers on: "create a PDF guide", "make a checklist PDF",
  "one-pager", "generate a report PDF", "PDF document".
---

# PDF Generator

Create professional PDF documents by orchestrating multiple skills in sequence.

## Pipeline (strict order)

### Phase 1: Brief
Clarify with user (ask only what's missing):
- Document type (checklist, one-pager, guide, report)
- Topic and key points
- Target audience
- Language
- Branding: colors, logo path, fonts (or use sensible defaults)

### Phase 2: Content (copywriting skill)
Load and follow the `copywriting` skill to write the text content.
- Apply all copywriting principles from the skill
- Structure content for the document type
- Write headlines, body, CTAs per copywriting guidelines

### Phase 3: Humanize (humanizer pass)
Run the humanizer checklist from the `copywriting` skill (Post-Generation section).
- Remove all AI vocabulary words
- Fix em dashes (replace with periods, commas, colons)
- Vary sentence length
- Remove chatbot artifacts
- Final check: no em dashes, no AI words, natural when read aloud

### Phase 4: Design + Build
Use the `pdf` skill (reportlab/pypdf) to build the actual PDF.

Design principles:
- Clean, minimal layout with generous whitespace
- Visual hierarchy: clear headings, body, callouts
- Brand colors consistently applied
- Icons or simple graphics where they add clarity
- Page numbers, header/footer with branding

Layout patterns by document type:
- **Checklist**: single page or 2-page, checkbox items, numbered sections
- **One-pager**: single page, dense but readable, clear sections
- **Guide**: cover page + content pages + CTA page
- **Report**: cover + TOC + content + summary

### Phase 5: Self-check
Before delivering, verify:
- [ ] Text passes humanizer checklist (no AI patterns)
- [ ] No em dashes in any text
- [ ] Design is consistent (colors, fonts, spacing)
- [ ] All content is factual (no invented stats)
- [ ] PDF opens correctly and all pages render
- [ ] File size is reasonable (< 5MB for text-based docs)

## Output
Save PDF to the project directory. Tell user the file path.
If issues found in self-check, fix and regenerate before delivering.
