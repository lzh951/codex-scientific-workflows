---
name: origin-ppt-ole-curve-edit
description: Replace selected source curves inside embedded Origin OLE charts in Microsoft PowerPoint while preserving editability, non-target curves, chart geometry, and slide previews.
---

# Origin PPT OLE Curve Edit

Use this skill when a PowerPoint deck contains an embedded Origin chart and the task is to replace or update selected plotted curves without converting the chart into a static image.

## Core Goal

Preserve two things at the same time:

- the editable Origin/OLE data layer;
- the visible PowerPoint slide preview.

Updating only one layer is not enough. A deck can look correct while the embedded Origin object is stale, or the Origin data can be correct while the PowerPoint preview image still displays old curves.

## Workflow

1. Open the deck with Microsoft PowerPoint COM and inventory the target OLE shapes.
2. Copy the source deck to a new output deck before editing.
3. Extract the target `ppt/embeddings/oleObject*.bin`.
4. Read the OLE `Contents` stream and save it as an Origin project.
5. Open the Origin project with `originpro`.
6. Identify the visible graph page and the worksheet columns bound to each visible plot.
7. Replace only the requested curve columns.
8. Preserve non-target visible plots and source columns unless the user explicitly asks to change them.
9. Patch the modified Origin project back into the OLE `Contents` stream.
10. Refresh the corresponding PowerPoint preview image when slide display matters.
11. Reopen the output deck, export screenshots, and verify visual appearance.
12. Activate the repaired OLE object from PowerPoint to confirm editability.

## Guardrails

- Do not use PNG, screenshot, or white-mask overlays when an OLE edit is requested.
- Do not delete unrelated visible curves.
- Preserve chart geometry unless the user asks for layout changes.
- Keep axes, ticks, tick labels, plotted curves, points, and symbols in the Origin/OLE layer.
- Keep labels, legends, arrows, and explanatory annotations PowerPoint-native when practical.
- Save to a new file unless the user explicitly requests overwriting.

## Output

Report:

- output deck path;
- source-to-target curve mapping;
- screenshot visual QA status;
- OLE activation status;
- any remaining uncertainty about preview refresh or editability.
