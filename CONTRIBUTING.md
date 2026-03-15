# Contributing to LEVER Protocol

## Build Agent

This repository is actively maintained by an automated build agent (Timmy). The agent:

- Commits with author `LEVER Bot <eric@diiant.com>`
- Runs spec audits, fixes bugs, and writes tests autonomously
- Updates `control-plane/build-plan.md` as tasks complete
- Logs issues to `control-plane/known-issues.md`

### Manual Contributions

If making manual changes:

1. Check `control-plane/build-plan.md` for current priorities
2. Check `control-plane/known-issues.md` for known problems
3. Run `forge build && forge test` before committing
4. The build agent will audit your changes in its next cycle

### Specification

- `CLAUDE.md` is the canonical protocol spec
- `SPEC/` contains per-contract specifications
- Deviations from spec must be logged in `known-issues.md`

*Last updated: 2026-03-15 16:47:04 ICT*