# Codex Scientific Workflows

Reusable OriginLab, PowerPoint, and Codex workflow notes for scientific figure maintenance.

This repository keeps the public, reusable part of a local research-figure workflow: controlling Origin from Python, validating editable Origin OLE objects inside PowerPoint, and preserving scientific figure editability without relying on static screenshot overlays.

## Maintenance Snapshot

- Scope: OriginLab, PowerPoint, editable OLE objects, and Codex-assisted scientific figure maintenance.
- Public validation: GitHub Actions runs a Python syntax check for the public tools.
- Public fixtures: `examples/` contains synthetic data only.
- Contribution scope: see `CONTRIBUTING.md` before opening issues or pull requests.

## What Is Included

The public scope is intentionally narrow:

1. **Origin batch plotting**
   - Import CSV/Excel-style data into Origin with `originpro`.
   - Plot selected X/Y columns.
   - Export PNG, SVG, EMF, or other Origin-supported formats.

2. **PowerPoint versioning before edits**
   - Copy a deck to a new non-overwriting version.
   - Open the new file directly when the workflow requires visual review.
   - Record a simple version sidecar for traceability.

3. **Origin OLE repair workflow**
   - Re-embed legacy Origin OLE charts with Origin 2026.
   - Separate visual correctness from real OLE editability.
   - Keep source curves, axes, ticks, and symbols in the Origin/OLE layer.

4. **Origin OLE style synchronization**
   - Match a target embedded Origin chart to a reference chart.
   - Keep labels, arrows, legends, and callouts PowerPoint-native when practical.
   - Avoid static screenshot overlays.

5. **Selected curve replacement inside OLE**
   - Replace selected curve data inside an embedded Origin OLE object without converting it to a picture.

6. **Experimental Codex plugin packaging**
   - Package reusable local workflows as Codex plugins.
   - Include an `origin-computer-use` preflight workflow for OriginLab Origin desktop control through Codex Computer Use.
   - Require screenshot-based verification before claiming a desktop-control workflow has run through.

## What Is Not Included

Private research datasets, project-specific analysis pipelines, manuscript-specific figures, and domain-specific calculations are deliberately excluded. The goal is to share the reusable workflow boundary around Origin, PowerPoint, OLE editability, and scientific figure quality control.

## Requirements

This toolkit is primarily for Windows scientific workflows.

- Python 3.10+
- Microsoft PowerPoint for PPT/PPTX visual review and OLE workflows
- OriginLab Origin with the `originpro` Python package for Origin automation
- `pywin32` for PowerPoint COM automation
- `pillow` for contact sheet generation

Install Python dependencies:

```powershell
python -m pip install -r requirements.txt
```

## Quick Examples

Inspect the included synthetic fixture:

```powershell
Get-Content .\examples\origin_batch_plot_sample.csv
```

Create a non-overwriting PowerPoint copy and open it:

```powershell
python .\tools\prepare_ppt_version.py "C:\path\to\source_deck.pptx" --suffix "origin_ole_fix" --out-dir "C:\path\to\output" --open
```

Create a simple Origin plot:

```powershell
python .\tools\origin_batch_plot.py --input "C:\path\to\data.csv" --x-col 0 --y-col 1 --output "C:\path\to\plot.emf" --plot-type l
```

## Workflow Principles

- Prefer real Origin/PowerPoint editability over rasterized screenshots.
- Keep data-bearing curves, axes, ticks, and symbols inside the Origin/OLE layer.
- Keep explanatory labels, arrows, guides, and callouts editable when practical.
- Export screenshots after every PPT edit and inspect them before delivery.
- Treat visual correctness and OLE editability as separate checks.
- Save modified decks as new files rather than overwriting source decks.

## Repository Layout

```text
.github/
  workflows/
    ci.yml
docs/
  CODEX_FOR_OSS_APPLICATION_DRAFT.md
  MAINTENANCE.md
examples/
  README.md
  origin_batch_plot_sample.csv
skills/
  origin-batch-plot/
  origin-ppt-ole-2026-reembed/
  origin-ppt-ole-curve-edit/
  origin-ppt-ole-style-sync/
plugins/
  origin-computer-use/
tools/
  origin_batch_plot.py
  prepare_ppt_version.py
CONTRIBUTING.md
```

## License

MIT License. See `LICENSE`.
