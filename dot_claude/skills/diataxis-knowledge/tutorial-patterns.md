# Tutorial Patterns

## What a Tutorial Is

A tutorial is a **lesson**. The author guides the reader through a learning experience. The reader does things, and learns through doing. The author is responsible for the reader's safety and success.

A tutorial is NOT a how-to guide. Tutorials teach; how-to guides direct.

## Structure Template

```markdown
# Getting Started

By the end of this guide, you will have [concrete achievement].

## Prerequisites

- [Exact tool with version]
- [Access or credentials needed]
- [Link to relevant setup if needed]

## Step 1: [Action with visible result]

[Single command or action]

Expected output:

\`\`\`
[Exact expected output]
\`\`\`

## Step 2: [Next action]

[Continue the pattern]

## Step N: [Final action]

[The achievement the reader was promised]

## Next steps

- [Link to how-to guides for real-world tasks]
- [Link to architecture for understanding the system]
- [Link to configuration for customization]
```

## Rules

### The Author Decides, the Reader Follows

- Every step is an instruction, not a choice
- Do not offer alternatives ("you could also...")
- Do not present options ("choose between X and Y")
- Alternatives belong in how-to guides

### Every Step Produces a Visible Result

- A command output the reader can compare
- A file that appears on disk
- A row in a table
- A page in a browser

If a step has no visible result, the reader cannot tell if they did it correctly. Restructure.

### Minimize Explanation

- Include only enough theory for the reader to proceed: "We use HTTPS because it's safer"
- Link to explanation docs for depth: "For details on the dual extraction architecture, see [Architecture](architecture.md)"
- Never stop the tutorial to teach a concept

### Start from a Known State

- State prerequisites exactly (tools, versions, credentials)
- Use a specific, reproducible example (a known-good record ID, a test dataset)
- The reader should be able to follow the tutorial verbatim and get the same results

### End with an Achievement

The final step should produce something the reader can see and verify:
- "You have processed your first invoice"
- "Your local environment is fully working"
- "The chatbot is running at http://localhost:8000"

### Use Expected Output Blocks

After every command, show what the reader should see:

```markdown
Expected output:

\`\`\`
Resolved 42 packages in 0.3s
Installed 42 packages in 0.1s
\`\`\`
```

The word "Expected" signals that the reader should compare their output.

## Common Mistakes in Tutorials

1. **Offering choices** — "You can use Docker or install locally" → Pick one path. Put the other in a how-to guide.
2. **Explaining architecture** — "The system uses a three-layer pipeline because..." → Link to `architecture.md`.
3. **Covering all error cases** — "If you see error X, try Y; if Z, try W" → Cover only the most common failure: "If this step fails, check that your API key is set."
4. **Skipping expected output** — The reader cannot verify their progress without it.
5. **Starting from an ambiguous state** — "Make sure your environment is set up" → List exact prerequisites.
6. **Ending without achievement** — "You're now ready to explore" → Instead: "You have deployed your first model."

## Tutorial Length

A tutorial should take 15-30 minutes to complete. If it takes longer:
- Split into multiple tutorials ("Getting Started Part 1: Local Setup", "Part 2: First Pipeline Run")
- Each part should end with its own achievement

## Connecting to Other Quadrants

At the end of a tutorial, always include a "Next steps" section linking to:
- **How-to guides**: "Now deploy to production: [How to Deploy](how-to-deploy.md)"
- **Explanation**: "Understand the architecture: [Architecture](architecture.md)"
- **Reference**: "See all configuration options: [Configuration](configuration.md)"
