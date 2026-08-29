---
name: origin-computer-use
description: Use when the user wants Codex to control or inspect OriginLab Origin's Windows desktop UI through Computer Use, verify whether Origin UI automation is runnable, or diagnose why Computer Use cannot reach an Origin window.
---

# Origin Computer Use

Use this skill for UI-level control of OriginLab Origin on Windows through Codex Computer Use. This skill complements, but does not replace, the existing `origin-batch-plot`, `origin-ppt-ole-2026-reembed`, `origin-ppt-ole-style-sync`, and `origin-ppt-ole-curve-edit` skills.

Use the Python or OLE skills first for deterministic data/plot/PPT edits. Use this skill when the task specifically needs visible Origin UI inspection, manual-style Origin interaction, window activation, or screenshot-based verification.

## Required Preflight

1. Load and follow the `computer-use` skill before any Windows UI automation.
2. Check passive local evidence first when needed:
   - running `Origin64.exe` processes,
   - installed Origin versions under `C:\Program Files\OriginLab\`,
   - active PowerPoint or OLE workflows that may already own an Origin instance.
3. Run a lightweight Computer Use probe:
   - initialize the Computer Use runtime,
   - call `sky.list_apps()`,
   - search app ids, display names, and window titles for `Origin`, `Origin64`, or `OriginLab`.
4. If the Computer Use probe reports unavailable, stopped, native pipe unavailable, or helper failure:
   - do not claim Origin UI control is working,
   - do not fall back to PowerShell `SendKeys` or foreground UI automation,
   - report the exact blocking condition,
   - optionally run `scripts/preflight_origin_computer_use.ps1` for passive local evidence only.

## Window Selection

After Origin is found through Computer Use:

1. Select exactly one Origin app candidate. If there are multiple candidates, prefer the user-requested Origin version; otherwise print a bounded candidate list and ask.
2. Select exactly one targetable Origin window. If there are multiple Origin windows, choose the main workspace or graph/workbook window relevant to the task.
3. Call `sky.get_window()` on the selected window.
4. Call `sky.activate_window({ window: targetWindow })`.
5. Call `sky.get_window_state({ window: targetWindow })` and visually inspect the screenshot before taking action.

## Launch Rules

- If Origin is discoverable but has no targetable window, launch it with `sky.launch_app({ app: targetApp.id })` and poll `sky.list_apps()`.
- If Origin is not discoverable from `sky.list_apps()`, use an explicit known executable path only when it exists, for example:
  - `C:\Program Files\OriginLab\Origin2026\Origin64.exe`
  - `C:\Program Files\OriginLab\Origin2025b\Origin64.exe`
  - `C:\Program Files\OriginLab\Origin2025\Origin64.exe`
- Do not start Origin through Windows Search, the Run dialog, File Explorer, or a terminal UI.

## Control Rules

- Use Computer Use input APIs only: `click`, `drag`, `press_key`, `type_text`, `scroll`, `set_value`, or `perform_secondary_action`.
- Prefer Origin's Python/COM APIs for structural plot/data changes when available; use UI actions only for visual inspection or tasks that cannot be done reliably through APIs.
- For graph/workbook work, verify the visible active page before acting.
- For menus and dialogs, prefer keyboard navigation after the screenshot confirms focus and modal state.
- Batch closely related actions, then verify once with `get_window_state`.
- Do not modify PowerPoint OLE objects through Origin UI unless the user asked for an OLE workflow and the appropriate Origin/PPT OLE skill has been considered.

## Success Criteria

Call the Origin Computer Use workflow "run through" only when all are true:

- Computer Use successfully returns `sky.list_apps()`.
- Origin is discovered or launched through Computer Use.
- A targetable Origin window is captured with a screenshot.
- At least one user-requested Origin UI action is performed through Computer Use.
- A follow-up screenshot verifies the action or visible state change.

If any item is missing, report the workflow status as partial or blocked.

## Passive Evidence Script

The plugin includes `scripts/preflight_origin_computer_use.ps1`. Use it only for passive checks when Computer Use is unavailable or when local installation evidence is needed. It does not automate the UI and cannot prove Computer Use control is working.
