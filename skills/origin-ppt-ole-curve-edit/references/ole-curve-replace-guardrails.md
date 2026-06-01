# OLE Curve Replace Guardrails

Use this reference when the requested result must remain an editable embedded Origin chart.

## Intent Check

- Identify whether the task is full-chart replacement or selected-curve replacement.
- If only one curve is requested, keep unrelated visible curves unchanged.
- If OLE editability is requested, do not switch to a picture overlay.

## Reliable Edit Path

1. Unzip the `.pptx`.
2. Locate the relevant `ppt/embeddings/oleObject*.bin`.
3. Extract the OLE `Contents` stream as an Origin project file.
4. Inspect visible graph pages and plot-to-column bindings in Origin.
5. Map incoming X/Y data to the exact target worksheet columns.
6. Preserve non-target columns and visible plots.
7. Resize worksheets before writing longer source series.
8. Save the modified Origin project.
9. Patch the project bytes back into the OLE `Contents` stream.
10. Export or refresh the PowerPoint preview image when needed.
11. Rezip the PPTX and verify in PowerPoint.

## Verification

- The modified OLE container still has a `Contents` stream.
- Visible plot count is unchanged unless intentionally changed.
- Non-target curves remain present.
- Source-to-target mapping is documented.
- The final slide screenshot matches the edited Origin graph.
- PowerPoint can activate the OLE object for editing.
