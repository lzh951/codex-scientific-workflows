---
name: origin-batch-plot
description: "Automate OriginLab plotting from Python using originpro or COM-backed APIs: import CSV or Excel data, choose X and Y columns, create a graph, apply an optional template, and export PNG, SVG, EMF, or other figure files. Use when users ask to batch import data into Origin, generate a reusable Origin plotting script, export standard figures, or avoid manual Origin UI steps."
---

# Origin Batch Plot

## Overview

Use this skill to build or run a minimal, reliable Python-to-Origin workflow for import, plotting, and export. Start from the bundled script and extend it only if the task truly needs more than one curve or basic figure settings.

## Workflow

1. Confirm the user wants Python-driven Origin automation rather than WPS or PPT OLE editing.
2. Confirm Origin is installed and Python can import `originpro`.
3. Normalize the request into input file path, X column, Y column, plot type, optional template, output path, and whether Origin should stay visible.
4. Prefer the bundled `scripts/origin_batch_plot.py` as the baseline implementation.
5. Run the script on a representative file and verify that the export exists.
6. Extend the script only when the user needs multi-curve plots, axis styling, legends, or project persistence.

## Guardrails

- Prefer the official `originpro` package. Treat hand-written COM fallback as a last resort.
- Use zero-based column indices, because the bundled script expects them.
- Do not assume an Origin template exists; verify the template name or file path first.
- Create output directories before export.
- Close Origin with `op.exit()` when running from external Python unless the user explicitly wants to inspect the UI after execution.

## Common Requests

- Batch import CSV and export line plots.
- Import Excel into Origin and export publication figures.
- Generate a reusable Python script for repeated Origin plots.
- Add a template switch or keep Origin visible for debugging.

## Example Command

```bash
python scripts/origin_batch_plot.py ^
  --input "C:\data\demo.csv" ^
  --x-col 0 ^
  --y-col 1 ^
  --output "C:\data\demo.png" ^
  --plot-type l ^
  --show-origin
```

## Resource

Use `scripts/origin_batch_plot.py` first. Patch it instead of rewriting a new script from scratch.
