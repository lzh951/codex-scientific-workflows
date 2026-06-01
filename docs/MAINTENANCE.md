# Maintenance Notes

This repository is maintained as a reusable workflow toolkit for OriginLab and PowerPoint figure work.

## Maintainer Responsibilities

- Keep Origin automation examples runnable and conservative.
- Preserve the distinction between visual correctness and editable OLE correctness.
- Add guardrails for failure modes found in real PowerPoint/Origin workflows.
- Keep Codex skill instructions aligned with the included tools.
- Avoid committing private data, presentation decks, OPJU files, screenshots, or project-specific analysis outputs.
- Close issues or pull requests that fall outside the Origin/PowerPoint/OLE scientific workflow scope.

## Current Public Modules

- Origin batch plotting from Python.
- PowerPoint versioning before edits.
- Codex skills for Origin OLE re-embedding, style synchronization, and selected curve replacement.
- Synthetic example data for smoke-testing public plotting workflows.
- GitHub Actions syntax checks for public Python tools.

## Triage Policy

- Accept only issues and pull requests tied to OriginLab, PowerPoint, editable OLE objects, Codex skill instructions, or scientific figure-maintenance workflows.
- Close unrelated demos, games, generated boilerplate, and private-data requests as out of scope.
- Prefer small, reviewable changes with public or synthetic test inputs.

## Release Checklist

1. Run Python syntax checks on `tools/*.py`.
2. Scan tracked files for private paths, credentials, and project-specific datasets.
3. Confirm generated QA folders and binary research artifacts are ignored.
4. Review skill docs for stale assumptions before publishing.
5. Confirm example files remain synthetic and small.
