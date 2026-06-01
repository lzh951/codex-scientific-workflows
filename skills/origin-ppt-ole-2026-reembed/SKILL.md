---
name: origin-ppt-ole-2026-reembed
description: Recover, re-embed, and validate Origin OLE charts in Microsoft PowerPoint using Origin 2026, especially when old Origin50/Origin95 objects look correct visually but fail, crash, or spawn Origin error reports when edited.
---

# Origin PPT OLE 2026 Re-embed

Use this skill when a `.ppt` or `.pptx` contains embedded Origin OLE charts that need to be opened, repaired, re-embedded, or proven editable with Origin 2026. The goal is not only visual correctness; the deliverable must survive actual PowerPoint OLE activation without launching stale Origin versions or error reporters.

## Required App Path

- Use Microsoft PowerPoint COM (`PowerPoint.Application`) for opening, editing, exporting previews, and validating OLE activation.
- Do not use WPS/KWPP unless the user explicitly asks for it or PowerPoint is unavailable. Report any fallback.
- Use Origin 2026 for the final embedded OLE objects.
- Never overwrite the source deck unless the user explicitly asks. Save repaired decks as new files.

## Preflight

1. Check current `POWERPNT`, `Origin64`, `CrashSender1402`, and `WerFault` processes before testing.
2. Do not kill the user's active PowerPoint, Origin, Codex, remote-control, or browser processes just because they are present.
3. Close only stale Origin error-report windows when needed, and only after identifying them by process name/window title.
4. Confirm the Origin OLE registry points to the intended Origin 2026 executable when handler drift is suspected.
5. Open the target deck visibly in PowerPoint and export a PNG preview before and after changes.

## Core Repair Workflow

1. Inventory each target slide and record every Origin OLE shape:
   - slide number,
   - shape name,
   - `OLEFormat.ProgID`,
   - left, top, width, height,
   - z-order if replacement may disturb layering.
2. Treat old `Origin50.Graph` or unexpected mixed ProgIDs as a risk even if the slide preview looks correct.
3. Extract the embedded OLE `Contents` stream from each target `ppt/embeddings/oleObject*.bin` into an Origin project file when re-embedding is required.
4. In a separate Origin/Python process, open the extracted project with `originpro` under Origin 2026 and copy the graph page as OLE, for example with `graph.copy_page('OLE')`.
5. In a separate PowerPoint COM process, paste the Origin 2026 clipboard OLE into the deck.
6. Restore the original shape geometry exactly:
   - set `LockAspectRatio = 0` before applying dimensions,
   - restore `Left`, `Top`, `Width`, and `Height`,
   - restore z-order relative to neighboring shapes when needed.
7. Preserve the data layer inside Origin/OLE. Keep real axes, ticks, tick labels, curves, points, and data symbols in the OLE/data source.
8. Keep labels, arrows, callouts, legends, and explanatory elements as PPT-native editable shapes when practical.

## Validation

1. Reopen the repaired deck in Microsoft PowerPoint.
2. Navigate to the target slide before selecting OLE shapes. PowerPoint COM may fail activation if the slide is not active.
3. Select each repaired OLE shape and run the edit activation path (`OLEFormat.DoVerb(1)` or equivalent double-click/Edit behavior).
4. Prefer Edit activation for validation. Origin 2026 may reject the `Open` verb even for a clean blank OLE object, so `Open` is not the primary pass/fail signal unless a known baseline succeeds.
5. After each activation, confirm:
   - `Origin64.exe` is running from the Origin 2026 path,
   - the Origin window responds,
   - no new `CrashSender1402` or `WerFault` process appears,
   - the shape still reports an expected Origin ProgID.
6. Export PNG previews of the final deck and visually inspect the target slides.
7. Do not call a deck fixed if only the PNG looks correct but old ProgIDs remain or activation spawns an error reporter.

## Reporting

Report three things concisely:

- output deck path,
- visual preview status,
- OLE activation status, including any old ProgIDs or error-report processes.

If activation works but an error reporter appears, call it a partial/incomplete repair and recommend full Origin 2026 re-embedding.
