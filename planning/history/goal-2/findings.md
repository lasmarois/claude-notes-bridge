# Findings: Roadmap Design

## Requirements
- Flexible, evolvable structure
- Integrated into project memory
- Guides without constraining
- Acknowledges unknowns explicitly

## Roadmap Format Options

### Option 1: Linear Milestones
Simple sequence of milestones with dates.
- **Pro:** Clear, easy to track
- **Con:** Rigid, doesn't handle pivots well

### Option 2: Milestone + Confidence Levels
Milestones with markers: `[committed]`, `[likely]`, `[exploratory]`
- **Pro:** Acknowledges uncertainty
- **Con:** Slightly more complex

### Option 3: Horizons
Near-term (detailed) → Mid-term (sketched) → Far-term (vision)
- **Pro:** Natural uncertainty gradient
- **Con:** May feel vague

### Chosen: Hybrid (Option 2 + 3)
- Use horizons for structure
- Use confidence markers within each horizon
- Include "Open Questions" that may change direction
- Include "Pivot Points" where discoveries may alter path

## Integration Points
- `planning/ROADMAP.md` — The document
- `.claude/CLAUDE.md` — Import via `@planning/ROADMAP.md`
- `.claude/rules/roadmap.md` — Instructions for using/updating

## Resources
- Goal-1 deliverable for technical direction
