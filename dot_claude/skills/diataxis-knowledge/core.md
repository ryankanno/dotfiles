# Core Principles

## 1. The Four Quadrants

Diataxis identifies four distinct documentation needs. Each need requires a fundamentally different kind of writing. The quadrants are not categories you sort content into — they are different modes of writing that serve different reader states.

### Tutorials (Learning-Oriented)

A tutorial is a **lesson** that takes the reader by the hand through a learning experience. The reader does things under guidance, and learns through doing — not through being told.

- The instructor (author) is responsible for the learner's success
- The learner follows steps, not choices
- Every step produces a visible, verifiable result
- Theory is minimized — link to Explanation docs instead
- The tutorial ends with a concrete achievement

**Analogy**: A driving lesson. The goal is confidence and skill, not arriving at a destination.

### How-To Guides (Task-Oriented)

A how-to guide addresses a **real-world goal** by providing practical directions. The reader is already competent and needs to get something done.

- The reader has a problem to solve or a goal to achieve
- Steps are practical and focused on the outcome
- No teaching, no theory — just directions
- Assumes competence — the reader can fill in gaps
- Multiple how-to guides can exist for the same system (different goals)

**Analogy**: A recipe. The reader wants the dish, not a cooking lesson.

### Reference (Information-Oriented)

Reference contains **technical descriptions** — facts the reader needs to work correctly. It is accurate, complete, neutral, and free of distraction.

- Describes the machinery and how to operate it
- Architecture mirrors the thing it describes (like a map)
- Neutral — not concerned with what the reader is doing
- Complete — every field, every option, every parameter
- No interpretation, no guidance, no tutorials

**Analogy**: An encyclopedia entry or a nautical chart.

### Explanation (Understanding-Oriented)

Explanation provides **context, background, and reasoning**. It answers "why?" and helps the reader understand the bigger picture.

- Circles around its subject, approaches from different angles
- Can contain opinions and take perspectives
- Connects concepts to each other and to the broader domain
- Serves reflection and understanding, not immediate action
- Often the most neglected quadrant

**Analogy**: An article on the history and philosophy behind a design decision.

---

## 2. The Two Axes

The four quadrants sit on two axes that define the Diataxis map:

### Axis 1: Action vs. Cognition

- **Tutorials and How-To Guides** are concerned with what the user **does** (action)
- **Reference and Explanation** are about what the user **knows** (cognition)

### Axis 2: Acquisition vs. Application

- **Tutorials and Explanation** serve the **acquisition** of skill (the user's study)
- **How-To Guides and Reference** serve the **application** of skill (the user's work)

These axes create the compass:

| If the content... | ...and serves the user's... | ...then it belongs to... |
|-------------------|----------------------------|--------------------------|
| Informs action | Acquisition of skill | A **tutorial** |
| Informs action | Application of skill | A **how-to guide** |
| Informs cognition | Application of skill | **Reference** |
| Informs cognition | Acquisition of skill | **Explanation** |

---

## 3. One Quadrant Per Page

This is the **most important rule**. Every documentation page belongs to exactly one quadrant. Mixing quadrants is the #1 anti-pattern in technical documentation.

### Why mixing fails

- A tutorial that stops to explain architecture loses the learner's momentum
- A reference page that includes step-by-step guides becomes unfocused and hard to scan
- A how-to guide that teaches concepts makes the competent user impatient
- An explanation page that includes CLI commands confuses the reader about what to do

### How to fix mixed pages

1. Identify which quadrant the page primarily serves
2. Extract content from other quadrants into separate pages
3. Replace extracted content with cross-references (links)

**Example**: A "Getting Started" page that explains the architecture halfway through should link to `architecture.md` instead: "For details on why the system uses dual extraction, see [Architecture](architecture.md)."

---

## 4. Quality Theory

Diataxis distinguishes two dimensions of documentation quality:

### Functional Quality (Measurable)

- **Accuracy**: content matches reality
- **Completeness**: no missing fields, options, or parameters
- **Consistency**: terminology and formatting are uniform
- **Usefulness**: content serves a real need
- **Precision**: content is specific, not vague

These are independent — you can measure each one. Failure in any area is immediately apparent to readers.

### Deep Quality (Recognizable but Unmeasurable)

- Feeling good to use
- Having flow — the reader never gets stuck
- Fitting to human needs
- Anticipating the reader — answering questions before they arise
- Being beautiful — clean structure, clear language

These are interdependent — you cannot have one without the others.

### The Relationship

Deep quality **depends on** functional quality. Documentation cannot feel good to use if it contains inaccuracies. Diataxis creates conditions for deep quality by organizing content around user needs, but it cannot guarantee functional quality alone.

---

## 5. Complex Hierarchies

When documentation grows large or serves multiple audiences, apply these patterns:

### The 7-Item Rule

Seven items is the comfortable limit per table of contents level. When a TOC exceeds this, restructure by adding intermediate organizational layers.

### Multiple Audiences

When different audiences perceive fundamentally different products, two approaches exist:

1. **Audience-first**: Organize by audience, then by Diataxis quadrants within each
2. **Quadrant-first**: Organize by Diataxis quadrants, then subdivide by audience

Choose based on whether audiences share more content than they diverge on. If audiences are highly distinct (e.g., end users vs. API developers), go audience-first.

### Diataxis Is Not Four Boxes

Diataxis is an **approach**, not a filing system. It identifies four different needs and tends toward structural division as an outcome. The structure should emerge from applying the framework, not from creating empty directories named "tutorials" and "reference."

### Shared Content

When multiple audiences need the same content, write it once and cross-reference it. Do not duplicate content across audience sections.

---

## 6. Cross-Referencing Between Quadrants

Readers navigate between quadrants naturally. Support this with explicit links:

| From | Link to | When |
|------|---------|------|
| Tutorial | How-To Guide | "Now that you've learned X, see [How to do Y](how-to-y.md) for real-world use" |
| Tutorial | Explanation | "For why we designed it this way, see [Architecture](architecture.md)" |
| How-To Guide | Reference | "For the complete list of options, see [Configuration](configuration.md)" |
| How-To Guide | Explanation | "For background on this approach, see [Design Decisions](design-decisions.md)" |
| Reference | How-To Guide | "For a walkthrough of this feature, see [How to Configure X](how-to-configure-x.md)" |
| Explanation | Reference | "For the full schema, see [Data Models](data-models.md)" |

---

## 7. Anti-Patterns

These violations of Diataxis principles are the most common and the most damaging:

1. **Mixing quadrants on a single page** — a tutorial that explains architecture, a reference page with step-by-step instructions
2. **Teaching in how-to guides** — explaining concepts when the reader needs directions
3. **Guiding in reference** — adding "you should" or step-by-step instructions to a facts page
4. **Explaining in tutorials** — stopping to explain why something works when the learner needs to keep moving
5. **Missing explanation entirely** — the most neglected quadrant; architecture and design decisions go unwritten
6. **Empty structure** — creating four empty directories before writing any content
7. **Duplicating content** — writing the same information in multiple quadrants instead of cross-referencing
8. **Using "Getting Started" as a dumping ground** — putting tutorials, setup guides, architecture overviews, and reference all in one page
9. **Treating README.md as documentation** — README is a landing page, not a doc; it links to docs
10. **Hardcoding project-specific details in framework rules** — Diataxis is universal; project-specific decisions go in DOCUMENTATION_GUIDE.md
