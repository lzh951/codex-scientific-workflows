---
name: origin-ppt-ole-style-sync
description: Synchronize a right-side Origin OLE chart to match a left reference chart in Microsoft PowerPoint `.pptx` files, including chart size, curve/axis thickness, and editable overlays (textboxes, arrows, dashed guides, axis labels, and tick values). Use when users ask to make two charts visually consistent, replace/tune embedded Origin OLE content, or rebuild figure annotations as PPT-editable objects.
---

# Origin PPT OLE Style Sync

## Overview

Use this skill to perform deterministic, repeatable edits to embedded Origin OLE charts while preserving PPT editability and layout.

## Office Engine Preference

- Use Microsoft PowerPoint COM (`PowerPoint.Application`) as the default PPT engine on this machine.
- Do not use WPS/KWPP for ordinary PPT editing, preview export, splitting, or visual inspection.
- Fall back to WPS/KWPP only if the user explicitly asks for WPS or Microsoft PowerPoint is unavailable and the fallback is reported clearly.
- After opening or activating a target PPT, move the PowerPoint main window to the Windows primary display and maximize it before handing off or visually inspecting.

## Workflow

1. Open the PPT and inspect shapes on each target slide.
2. Identify:
   - left reference chart (usually picture/finished style),
   - right target Origin OLE,
   - nearby annotation shapes.
3. Extract right OLE content (`ppt/embeddings/oleObject*.bin` -> OLE `Contents` -> `.opju`) when style tuning is needed.
4. Tune Origin graph style in a separate Python process (`originpro`) to avoid COM conflicts.
5. Reopen PPT in another process with `PowerPoint.Application` and replace right OLE with tuned OPJU.
6. Match right OLE geometry to left chart geometry (size and top alignment).
7. Rebuild right-side annotations as editable PPT shapes/textboxes.
8. Save as a new file and verify slide-by-slide.

## Critical Guardrails

- Use process split for reliability:
  - Process A: Origin (`originpro`) tune/save OPJU.
  - Process B: Microsoft PowerPoint COM replace OLE and shape edits.
- Use `pythoncom.CoInitialize()` and `CoUninitialize()` in the same process.
- Do not overwrite source PPT unless user explicitly requests it.
- Keep all new labels/arrows/guides editable in PPT (no rasterized overlays).
- Preserve the academic data layer inside OLE/data plots: axes, tick marks, tick-value labels, plotted curves/lines, data points, and necessary data symbols must not be converted into free PPT lines/shapes just for editability.
- Move editability to the annotation layer: legends, explanatory text, labels, callouts, arrows, scale bars, and similar interpretation elements should be PPT-native editable objects when practical.
- If a legend is removed from Origin/OLE because it should not be locked there, recreate that legend in PowerPoint as editable text/line/marker objects. Do not simply delete it, and do not use white masks or screenshot covers.
- For line plots and point-line plots, prefer direct PPT-native labels placed near the corresponding curve, point cluster, or plotted element. Avoid detached standalone legends unless direct labels would make the figure more confusing.
- For ordered experimental series such as temperature, frame number, distance, time, loading step, or other measurement sequences, use point-line plots when both discrete observations and trend continuity are scientifically meaningful.
- Tiny in-panel text should either be made readable at final figure size or moved out; do not leave unreadable micro-labels as pseudo-annotations.
- When Origin/OLE text contains Chinese characters or full-width Chinese punctuation, never force the whole text object to `Times New Roman`. Split Latin/math text and CJK text into suitable fonts, or use a CJK-capable font such as `SimSun`/`Microsoft YaHei` for the affected text object. Verify exported previews for square-box glyphs before considering the OLE work complete.

## Shape Handling Rules

- Treat both as line-like candidates:
  - `Type=9` (`msoLine`)
  - `Type=1` (`msoAutoShape`) with empty text and visible line formatting
- Prefer explicit object creation or copy/paste over fragile bulk duplication:
  - textboxes: `Copy()` + `Paste()`
  - lines/arrows: recreate via `AddLine(...)`, then copy line style properties
- Keep right-side cleanup conservative to avoid deleting left-side labels.

## Style Sync Rules

- Match right OLE width/height to left reference chart.
- Match axis thickness and curve line width inside Origin graph.
- Clone annotation semantics from left to right:
  - axis titles,
  - tick labels,
  - arrows and guide lines,
  - small letters/legend-like text blocks.
- Preserve existing left chart content.

## Verification Checklist

1. Confirm output PPT exists and opens.
2. Confirm each target slide still contains one right Origin OLE.
3. Confirm right OLE size equals left reference chart size.
4. Confirm right-side text/line counts are reasonable and non-empty.
5. Confirm no left annotations were removed.
6. Confirm visual parity (thickness, label density, arrows/guides).

## References

- Read [references/ppt-ole-style-sync-checklist.md](references/ppt-ole-style-sync-checklist.md) for a runnable checklist.
