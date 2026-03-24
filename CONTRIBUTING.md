# Contributing to LEVER Protocol

## Build Agent

This repo is maintained by an automated build agent (Timmy) that:
- Commits as `LEVER Bot <eric@diiant.com>`
- Runs spec audits, fixes bugs, writes tests autonomously
- Updates `control-plane/build-plan.md` as tasks complete
- Logs issues to `control-plane/known-issues.md`

## Manual Changes

1. Check `control-plane/build-plan.md` for current priorities
2. Check `control-plane/known-issues.md` for known problems
3. Run `forge build && forge test` before committing
4. The build agent will audit your changes in its next cycle

## Specification

- `CLAUDE.md` is the canonical protocol spec
- `SPEC/` contains per-contract specifications
- Deviations from spec must be logged in `known-issues.md`

*Last updated: 2026-03-23 09:06:49 ICT*