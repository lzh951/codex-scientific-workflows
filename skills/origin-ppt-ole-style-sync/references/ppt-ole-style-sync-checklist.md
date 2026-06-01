# PPT OLE Style Sync Checklist

## Inputs

- Source `.pptx` path.
- Target slide indexes.
- Left reference chart on each target slide.
- Right Origin OLE to be synchronized.

## Execution Steps

1. Copy source PPT to a new output file.
2. Parse slide shapes and record:
   - left chart box `(left, top, width, height)`,
   - right OLE box,
   - left-side annotation shapes.
3. Extract `opju` from `ppt/embeddings/oleObject*.bin` stream `Contents`.
4. Tune Origin graph:
   - increase curve line width,
   - increase axis thickness,
   - keep axis labels visible.
5. Replace right OLE with tuned OPJU.
6. Set right OLE `width/height` equal to left chart and align top.
7. Rebuild right annotations:
   - copy/paste textboxes,
   - recreate lines/arrows with `AddLine` and copied line style.
8. Save and close COM objects in `finally`.

## PowerPoint COM Reliability Notes

- Prefer `PowerPoint.Application` first for PPT editing, export, splitting, and inspection.
- Use `kwpp.application` only when the user explicitly requests WPS or PowerPoint is unavailable, and report that fallback.
- Avoid mixed Origin COM + PPT COM in the same Python process.
- Retry paste operations when shape count does not increase immediately.
- If cleanup is needed, delete only right/bridge-region overlay objects.

## Quality Gates

- Right OLE remains editable as Origin object.
- Added labels/arrows are editable PPT objects.
- No missing direction arrows or process labels after rebuild.
- No unintended deletion on left chart.
