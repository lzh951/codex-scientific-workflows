# Contributing

This repository accepts changes that improve reusable scientific workflows around OriginLab, PowerPoint, editable OLE objects, and Codex skill instructions.

## In Scope

- Origin automation helpers that use public or synthetic input data.
- PowerPoint versioning, visual review, or OLE validation helpers.
- Codex skill instructions for repeatable scientific figure-maintenance workflows.
- Documentation that makes the workflow safer, clearer, or easier to reproduce.
- Small examples that run without private research data.

## Out of Scope

- Games, demos, or general scripts unrelated to scientific figure maintenance.
- Private research datasets, manuscript-specific figures, OPJU/PPTX binaries, screenshots, or lab-specific analysis pipelines.
- Credentials, API keys, local machine paths, or personal project notes.
- Changes that replace editable Origin or PowerPoint content with static screenshot overlays.

## Pull Request Checklist

Before opening a pull request:

1. Keep the change within the repository scope.
2. Run `python -m py_compile tools/*.py` when Python files change.
3. Use synthetic or public data in examples.
4. Do not commit generated QA output, binary decks, Origin project files, or local cache folders.
5. Explain whether the change affects visual fidelity, OLE editability, or both.
