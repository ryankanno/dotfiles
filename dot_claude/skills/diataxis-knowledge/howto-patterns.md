# How-To Guide Patterns

## What a How-To Guide Is

A how-to guide provides **practical directions** to help a competent user achieve a real-world goal. The reader has a problem to solve. The guide tells them how to solve it.

A how-to guide is NOT a tutorial. It does not teach. It assumes competence.

## Structure Template

```markdown
# How to [verb] [object]

[One-sentence description of what this guide accomplishes.]

## Prerequisites

- [What the reader needs before starting]

## Step 1: [Action]

[Practical direction]

## Step 2: [Action]

[Continue]

## Step N: [Verification]

[How to confirm success]

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| [Symptom] | [Root cause] | [Action] |
```

## Rules

### Goal-Oriented, Not Learning-Oriented

- The reader wants to **get something done**, not learn how things work
- Open with what the guide achieves, not with background
- Every step advances toward the goal

### Assume Competence

- The reader knows the domain — do not explain basic concepts
- Do not teach terminology — the reader already knows it
- If background is needed, link to an explanation page

### Focus on the Problem, Not the Tool

- Title: "How to deploy" not "Using the deployment system"
- Organize around goals, not around features
- Multiple how-to guides can cover the same system from different angles

### Include Practical Variations

Unlike tutorials (which follow one path), how-to guides should address common variations:

```markdown
## Deploy to dev via CI/CD

1. Push to `develop` branch
2. Pipeline triggers automatically

## Deploy manually (emergency)

1. Run `helm upgrade --install ...`
```

### End with Verification

Every how-to guide should tell the reader how to confirm success:

```markdown
## Verify

\`\`\`bash
kubectl get pods -n ai
\`\`\`

The application is available at `http://localhost:8000`.
```

### Include Troubleshooting

A troubleshooting table at the end handles common failure scenarios:

```markdown
## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Pod CrashLoopBackOff | Missing env vars | Check `.env` has all required values |
| DefaultAzureCredential failed | `az login` expired | Run `az login` on host |
```

## Common Mistakes in How-To Guides

1. **Teaching concepts** — "The pipeline uses a 9-stage architecture because..." → Link to `architecture.md`.
2. **Only one path** — How-to guides should cover practical variations (local, dev, prod).
3. **No verification step** — The reader cannot confirm success without it.
4. **No troubleshooting** — Common failures should be documented, not discovered by the reader.
5. **Too much detail** — Include enough to complete the task, not everything about the system.
6. **Mixing with reference** — "Here is the complete list of all 47 environment variables..." → Link to `configuration.md`.

## How-To Guide Naming

Always use the `how-to-<verb>.md` pattern:
- `how-to-deploy.md`
- `how-to-add-provider.md`
- `how-to-run-pipeline.md`
- `how-to-configure-ai-models.md`
- `how-to-run-evals.md`

The verb makes the goal clear in the filename.

## Connecting to Other Quadrants

Within a how-to guide, link to:
- **Reference**: "For the complete list of parameters, see [Configuration](configuration.md)"
- **Explanation**: "For background on this design, see [Design Decisions](design-decisions.md)"
- **Tutorial**: only if the reader may need to set up first: "If you haven't set up yet, see [Getting Started](getting-started.md)"
