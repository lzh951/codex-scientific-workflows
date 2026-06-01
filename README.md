# Codex Scientific Workflows

Reusable OriginLab, PowerPoint, and Codex workflow notes for scientific figure maintenance.

This repository keeps the public, reusable part of a local research-figure workflow: controlling Origin from Python, validating editable Origin OLE objects inside PowerPoint, and preserving scientific figure editability without relying on static screenshot overlays.

## What Is Included

The public scope is intentionally narrow:

1. **Origin batch plotting**
   - Import CSV/Excel-style data into Origin with `originpro`.
   - Plot selected X/Y columns.
   - Export PNG, SVG, EMF, or other Origin-supported formats.

2. **PowerPoint visual and OLE audit**
   - Export slide screenshots for visual QA.
   - Inventory shapes, geometry, and embedded Origin OLE objects.
   - Produce a contact sheet for quick review.

3. **Origin OLE activation check**
   - Open a deck with Microsoft PowerPoint COM.
   - Attempt edit activation for embedded Origin OLE shapes.
   - Detect stale ProgIDs, failed activation, or Origin error reporters.

4. **Origin project data audit**
   - Inspect OPJ/OPJU workbooks, sheets, columns, graph pages, and plotted data bindings.
   - Export graph previews for source verification.

5. **Codex skills for Origin/PPT workflows**
   - Re-embed legacy Origin OLE charts with Origin 2026.
   - Synchronize an Origin OLE chart with a visual reference while keeping annotations editable.
   - Replace selected curve data inside an embedded Origin OLE object without converting it to a picture.

## What Is Not Included

Private research datasets, project-specific analysis pipelines, manuscript-specific figures, and domain-specific calculations are deliberately excluded. The goal is to share the reusable workflow boundary around Origin, PowerPoint, OLE editability, and scientific figure quality control.

## Requirements

This toolkit is primarily for Windows scientific workflows.

- Python 3.10+
- Microsoft PowerPoint for PPT/PPTX visual QA and OLE activation checks
- OriginLab Origin with the `originpro` Python package for Origin automation
- `pywin32` for PowerPoint COM automation
- `pillow` for contact sheet generation

Install Python dependencies:

```powershell
python -m pip install -r requirements.txt
```

## Quick Examples

Create a non-overwriting PowerPoint copy and open it:

```powershell
python .\tools\prepare_ppt_version.py "C:\path\to\source_deck.pptx" --suffix "origin_ole_fix" --out-dir "C:\path\to\output" --open
```

Export slide screenshots and audit embedded Origin OLE objects:

```powershell
python .\tools\ppt_visual_ole_audit.py "C:\path\to\deck.pptx" --out "C:\path\to\qa_output"
```

Validate that Origin OLE charts can be activated for editing:

```powershell
python .\tools\ppt_origin_ole_activation_check.py "C:\path\to\deck.pptx" --slides "1,3" --out "C:\path\to\ole_activation_check"
```

Audit an Origin project file:

```powershell
python .\tools\origin_opju_data_audit.py "C:\path\to\source.opju" --out "C:\path\to\opju_audit"
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
docs/
  CODEX_FOR_OSS_APPLICATION_DRAFT.md
  MAINTENANCE.md
skills/
  origin-batch-plot/
  origin-ppt-ole-2026-reembed/
  origin-ppt-ole-curve-edit/
  origin-ppt-ole-style-sync/
tools/
  origin_batch_plot.py
  origin_opju_data_audit.py
  ppt_origin_ole_activation_check.py
  ppt_visual_ole_audit.py
  prepare_ppt_version.py
```

## License

MIT License. See `LICENSE`.
