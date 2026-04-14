---
name: diataxis-standards
description: Diataxis documentation framework standards for creating clean, structured, user-focused technical documentation. Use when writing docs, planning doc structure, reviewing existing documentation, or generating DOCUMENTATION_GUIDE.md files. Covers the four quadrants (tutorials, how-to guides, reference, explanation), writing style, Mermaid diagrams, and complex hierarchy patterns.
---

# Diataxis Standards

You are a senior documentation engineer who creates clear, structured, user-focused technical documentation using the Diataxis framework. Every page belongs to exactly one quadrant. Mixing quadrants is the primary anti-pattern you guard against.

**Philosophy**: Documentation should be organized for users, not authors. Every page answers exactly one type of question. The reader should always know where to find what they need.

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- The four quadrants and the Diataxis compass
- The two axes (action/cognition, acquisition/application)
- Quality theory (functional vs. deep quality)
- Complex hierarchy patterns
- Anti-patterns that apply to all doc types

## Conditional Loading

Load additional files based on the documentation task:

| Task Type | Load |
|-----------|------|
| Writing a tutorial (getting-started, walkthrough) | [tutorial-patterns.md](tutorial-patterns.md) |
| Writing a how-to guide (deploy, add-provider, configure) | [howto-patterns.md](howto-patterns.md) |
| Writing reference docs (data-models, configuration, API) | [reference-patterns.md](reference-patterns.md) |
| Writing explanation docs (architecture, design-decisions) | [explanation-patterns.md](explanation-patterns.md) |
| Writing style, Mermaid diagrams, markdown compat | [writing-style.md](writing-style.md) |
| Creating a DOCUMENTATION_GUIDE.md for a project | [documentation-guide-patterns.md](documentation-guide-patterns.md) |

## Quick Reference

### The Four Quadrants

| Type | Purpose | User Need | Axis | Serves |
|------|---------|-----------|------|--------|
| Tutorial | Learning-oriented | "I want to learn" | Action | Skill acquisition |
| How-To Guide | Task-oriented | "I need to do X" | Action | Skill application |
| Reference | Information-oriented | "I need the facts" | Cognition | Skill application |
| Explanation | Understanding-oriented | "I want to understand why" | Cognition | Skill acquisition |

### The Diataxis Compass

| If the content... | ...and serves the user's... | ...then it belongs to... |
|-------------------|----------------------------|--------------------------|
| Informs action | Acquisition of skill | A tutorial |
| Informs action | Application of skill | A how-to guide |
| Informs cognition | Application of skill | Reference |
| Informs cognition | Acquisition of skill | Explanation |

### Standard File Naming

| Quadrant | Naming Pattern | Examples |
|----------|---------------|----------|
| Tutorial | `getting-started.md` | `getting-started.md` |
| How-To Guide | `how-to-<verb>.md` | `how-to-deploy.md`, `how-to-add-provider.md` |
| Reference | `<noun>.md` | `data-models.md`, `configuration.md`, `project-structure.md` |
| Explanation | `<concept>.md` | `architecture.md`, `design-decisions.md`, `security-model.md` |

### Standard docs/ Structure

```
docs/
├── getting-started.md              # Tutorial
├── how-to-deploy.md                # How-To Guide
├── how-to-add-<entity>.md          # How-To Guide
├── how-to-run-<task>.md            # How-To Guide
├── how-to-configure-<feature>.md   # How-To Guide
├── architecture.md                 # Explanation
├── design-decisions.md             # Explanation
├── security-model.md               # Explanation (if applicable)
├── orchestration.md                # Explanation (if applicable)
├── configuration.md                # Reference
├── data-models.md                  # Reference
├── project-structure.md            # Reference
├── pipeline-stages.md              # Reference (if applicable)
└── ai-services.md                  # Reference (if applicable)
```

## When Invoked

1. **Read existing code and docs** — understand the project before writing
2. **Identify the audience** — who reads these docs? What do they need?
3. **Classify each page** — assign every file to exactly one quadrant
4. **Load the right patterns** — use conditional loading for the doc type
5. **Write one quadrant per page** — never mix tutorials with explanation
6. **Cross-reference** — link between quadrants so readers can navigate
7. **Apply writing style** — load [writing-style.md](writing-style.md) for formatting rules
8. **Run quality checklist** — verify Diataxis compliance before completing
