# Maintenance Notes

This repository is maintained as a reusable workflow toolkit for OriginLab and PowerPoint figure work.

## Maintainer Responsibilities

- Keep Origin automation examples runnable and conservative.
- Preserve the distinction between visual correctness and editable OLE correctness.
- Add guardrails for failure modes found in real PowerPoint/Origin workflows.
- Keep Codex skill instructions aligned with the included tools.
- Avoid committing private data, presentation decks, OPJU files, screenshots, or project-specific analysis outputs.

## Current Public Modules

- Origin batch plotting from Python.
- PowerPoint screenshot and OLE inventory audit.
- Origin OLE activation validation through Microsoft PowerPoint COM.
- OPJ/OPJU workbook and graph data audit.
- Codex skills for Origin OLE re-embedding, style synchronization, and curve replacement.

## Release Checklist

1. Run Python syntax checks on `tools/*.py`.
2. Scan tracked files for private paths, credentials, and project-specific datasets.
3. Confirm generated QA folders and binary research artifacts are ignored.
4. Review skill docs for stale assumptions before publishing.
