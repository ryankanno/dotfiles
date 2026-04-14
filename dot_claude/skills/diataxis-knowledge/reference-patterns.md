# Reference Patterns

## What Reference Is

Reference documentation contains **technical descriptions** — facts the reader needs to do things correctly. It is accurate, complete, neutral, and free of distraction. It describes the machinery and how to operate it.

Reference is NOT a tutorial or how-to guide. It does not teach or guide — it describes.

## Structure Template

```markdown
# [System/Component Name]

[One-sentence description of what this documents.]

Source: `path/to/source/code/`

## Section 1: [Subsystem]

### [Entity Name]

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `field_name` | STRING | Yes | What this field contains |

## Section N: [Subsystem]

[Continue the pattern — the structure mirrors the thing it describes]
```

## Rules

### Architecture Mirrors the Subject

The structure of reference documentation should reflect the structure of the thing it describes — like a map reflects geography.

- If the code has modules, the reference has sections per module
- If a table has columns, the reference has a row per column
- If an API has endpoints, the reference has an entry per endpoint
- If an enum has values, the reference has a row per value

### Complete and Exhaustive

Every field, every option, every parameter, every enum value must be documented. Completeness is the primary measure of reference quality.

- Every config class → every field with type, default, description
- Every database table → every column with type, constraints, description
- Every enum → every value with meaning
- Every CLI flag → description and default

### Neutral and Factual

Reference does not interpret, recommend, or guide:

```markdown
<!-- CORRECT: Neutral description -->
| `batch_size` | int | `20` | Number of records per processing batch |

<!-- WRONG: Contains guidance -->
| `batch_size` | int | `20` | Number of records per batch. We recommend 20 for most cases. |
```

Recommendations belong in how-to guides or explanation.

### Source Attribution

Reference should cite where the information comes from:

```markdown
Source: `src/agentic_chatbot_web/settings/`
```

This helps the reader verify the documentation against the code and find the implementation.

## Reference Document Types

### Configuration Reference

Documents all environment variables, config classes, and their defaults:

```markdown
## AzureConfig

| Field | Env var | Type | Default | Required |
|-------|---------|------|---------|----------|
| `endpoint` | `AZURE_SEARCH_ENDPOINT` | `str | None` | `None` | For search agent |
```

### Data Models Reference

Documents database tables, ORM models, Pydantic models, and enums:

```markdown
## Database Tables

### users

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | Primary key |
```

### Project Structure Reference

Documents directory layout and module responsibilities:

```markdown
## Directory Tree

\`\`\`
src/
├── agents/          # Agent implementations
├── services/        # Business logic
└── settings/        # Configuration
\`\`\`

## Source Modules

| Module | Role | Key Exports |
|--------|------|-------------|
| `app.py` | Entry point | `asgi_app` |
```

### API Reference

Documents endpoints, parameters, request/response schemas:

```markdown
## POST /api/v1/extract

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file` | binary | Yes | PDF or image file |
```

## Common Mistakes in Reference

1. **Including guidance** — "You should set this to..." → That is a how-to guide.
2. **Incomplete coverage** — Missing fields, missing enum values, missing options.
3. **Structure that does not mirror the subject** — Organizing by importance instead of by code structure.
4. **Stale content** — Fields that exist in code but not in docs, or vice versa.
5. **Mixing with how-to** — "To configure this, first run..." → Link to `how-to-configure.md`.
6. **Narrative prose** — Reference should be tables, lists, and structured entries — not paragraphs.

## Connecting to Other Quadrants

Within reference docs, link to:
- **How-to guides**: "For a walkthrough of deployment, see [How to Deploy](how-to-deploy.md)"
- **Explanation**: "For why this architecture was chosen, see [Design Decisions](design-decisions.md)"
