from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import pythoncom
    import win32com.client
except ImportError as exc:  # pragma: no cover - Windows/COM dependent
    raise SystemExit("Missing pywin32. Run this on the Windows machine with PowerPoint installed.") from exc

from ppt_visual_ole_audit import parse_slide_spec, safe_print


PROCESS_NAMES = ["POWERPNT", "Origin64", "CrashSender1402", "WerFault"]
POWERPOINT_EXE = Path(r"C:\Program Files\Microsoft Office\Root\Office16\POWERPNT.EXE")


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields = list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def process_snapshot() -> list[dict[str, Any]]:
    script = (
        "$names = @('POWERPNT','Origin64','CrashSender1402','WerFault');"
        "Get-Process -Name $names -ErrorAction SilentlyContinue | "
        "Select-Object ProcessName,Id,Path,MainWindowTitle | ConvertTo-Json -Compress"
    )
    try:
        completed = subprocess.run(
            ["powershell", "-NoProfile", "-Command", script],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except Exception:
        return []
    text = completed.stdout.strip()
    if not text:
        return []
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return [{"ProcessName": "SNAPSHOT_PARSE_ERROR", "Id": "", "Path": "", "MainWindowTitle": text[:500]}]
    if isinstance(parsed, dict):
        parsed = [parsed]
    rows: list[dict[str, Any]] = []
    for row in parsed:
        rows.append(
            {
                "process_name": row.get("ProcessName", ""),
                "pid": row.get("Id", ""),
                "path": row.get("Path", ""),
                "window_title": row.get("MainWindowTitle", ""),
            }
        )
    return rows


def pids(rows: list[dict[str, Any]], process_name: str) -> set[int]:
    out: set[int] = set()
    for row in rows:
        if str(row.get("process_name", "")).lower() != process_name.lower():
            continue
        try:
            out.add(int(row.get("pid", "")))
        except (TypeError, ValueError):
            pass
    return out


def rows_for(rows: list[dict[str, Any]], process_name: str) -> list[dict[str, Any]]:
    return [row for row in rows if str(row.get("process_name", "")).lower() == process_name.lower()]


def shape_progid(shape: Any) -> str:
    try:
        return str(shape.OLEFormat.ProgID)
    except Exception:
        return ""


def safe_float(value: Any) -> float | None:
    try:
        return float(value)
    except Exception:
        return None


def dispatch_powerpoint() -> tuple[Any, str, bool]:
    try:
        return win32com.client.DispatchEx("PowerPoint.Application"), "DispatchEx", True
    except Exception as first_exc:
        errors = [f"DispatchEx: {type(first_exc).__name__}: {first_exc}"]

    existing_powerpoint = bool(pids(process_snapshot(), "POWERPNT"))
    if not existing_powerpoint and POWERPOINT_EXE.exists():
        try:
            subprocess.Popen([str(POWERPOINT_EXE)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as exc:
            errors.append(f"start POWERPNT.EXE: {type(exc).__name__}: {exc}")

    last_exc: Exception | None = None
    for _ in range(20):
        try:
            return win32com.client.Dispatch("PowerPoint.Application"), "StartProcess+Dispatch", not existing_powerpoint
        except Exception as exc:
            last_exc = exc
            time.sleep(1)
    if last_exc is not None:
        errors.append(f"Dispatch after start: {type(last_exc).__name__}: {last_exc}")
    raise RuntimeError("; ".join(errors))


def is_powerpoint_app(app: Any) -> bool:
    try:
        return "powerpoint" in str(app.Name).lower()
    except Exception:
        return True


def open_presentation_for_check(app: Any, ppt_path: Path) -> tuple[Any, str]:
    # Prefer an untitled copy: it allows OLE activation while avoiding source overwrite.
    modes = [
        ("untitled_copy", (False, True, True)),
        ("editable_original_no_save", (False, False, True)),
        ("readonly_original", (True, False, True)),
    ]
    errors: list[str] = []
    for label, args in modes:
        try:
            return app.Presentations.Open(str(ppt_path), *args), label
        except Exception as exc:
            errors.append(f"{label}: {type(exc).__name__}: {exc}")
    raise RuntimeError("; ".join(errors))


def goto_slide(app: Any, slide_index: int) -> None:
    try:
        app.ActiveWindow.View.GotoSlide(slide_index)
    except Exception:
        try:
            app.ActivePresentation.Slides(slide_index).Select()
        except Exception:
            pass


def collect_origin_shapes(presentation: Any, slide_filter: set[int] | None) -> list[dict[str, Any]]:
    slide_count = int(presentation.Slides.Count)
    selected = slide_filter or set(range(1, slide_count + 1))
    rows: list[dict[str, Any]] = []
    for slide_index in range(1, slide_count + 1):
        if slide_index not in selected:
            continue
        slide = presentation.Slides(slide_index)
        for shape_index in range(1, int(slide.Shapes.Count) + 1):
            shape = slide.Shapes(shape_index)
            progid = shape_progid(shape)
            if "Origin" not in progid:
                continue
            rows.append(
                {
                    "slide": slide_index,
                    "shape_index": shape_index,
                    "shape_name": str(getattr(shape, "Name", "")),
                    "progid": progid,
                    "left": safe_float(getattr(shape, "Left", None)),
                    "top": safe_float(getattr(shape, "Top", None)),
                    "width": safe_float(getattr(shape, "Width", None)),
                    "height": safe_float(getattr(shape, "Height", None)),
                }
            )
    return rows


def origin_path_status(
    after_rows: list[dict[str, Any]],
    expected_origin_path_contains: str,
) -> tuple[str, str]:
    origin_rows = rows_for(after_rows, "Origin64")
    if not origin_rows:
        return "warning", "Origin64.exe not observed after activation."
    if not expected_origin_path_contains:
        paths = "; ".join(str(row.get("path", "")) for row in origin_rows)
        return "pass", paths
    needle = expected_origin_path_contains.lower()
    matched = [row for row in origin_rows if needle in str(row.get("path", "")).lower()]
    if matched:
        return "pass", "; ".join(str(row.get("path", "")) for row in matched)
    paths = "; ".join(str(row.get("path", "")) for row in origin_rows)
    return "fail", f"Origin64 path does not contain '{expected_origin_path_contains}': {paths}"


def activate_shape(
    app: Any,
    presentation: Any,
    row: dict[str, Any],
    wait_seconds: float,
    expected_origin_path_contains: str,
) -> dict[str, Any]:
    slide_index = int(row["slide"])
    shape_index = int(row["shape_index"])
    before = process_snapshot()
    before_error_pids = pids(before, "CrashSender1402") | pids(before, "WerFault")
    activation_error = ""

    try:
        goto_slide(app, slide_index)
        shape = presentation.Slides(slide_index).Shapes(shape_index)
        try:
            shape.Select()
        except Exception:
            pass
        shape.OLEFormat.DoVerb(1)
    except Exception as exc:
        activation_error = f"{type(exc).__name__}: {exc}"

    if wait_seconds > 0:
        time.sleep(wait_seconds)
    after = process_snapshot()
    after_error_pids = pids(after, "CrashSender1402") | pids(after, "WerFault")
    new_error_pids = sorted(after_error_pids - before_error_pids)
    path_status, path_detail = origin_path_status(after, expected_origin_path_contains)

    if activation_error:
        status = "fail"
    elif new_error_pids:
        status = "fail"
    else:
        status = path_status

    return {
        **row,
        "activation_status": status,
        "activation_error": activation_error,
        "origin_path_status": path_status,
        "origin_path_detail": path_detail,
        "new_error_reporter_pids": ";".join(str(pid) for pid in new_error_pids),
        "origin_process_count_after": len(rows_for(after, "Origin64")),
        "checked_at": datetime.now().isoformat(timespec="seconds"),
    }


def run_activation_check(
    ppt_path: Path,
    out_dir: Path,
    slide_filter: set[int] | None,
    wait_seconds: float,
    max_objects: int,
    expected_origin_path_contains: str,
    inventory_only: bool,
) -> dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    before_rows = process_snapshot()
    write_csv(out_dir / "process_before.csv", before_rows)

    pythoncom.CoInitialize()
    app = None
    presentation = None
    inventory_rows: list[dict[str, Any]] = []
    result_rows: list[dict[str, Any]] = []
    open_error = ""
    open_mode = ""
    visible_error = ""
    dispatch_method = ""
    owns_app = False
    try:
        app, dispatch_method, owns_app = dispatch_powerpoint()
        if not is_powerpoint_app(app):
            raise RuntimeError("COM object is not Microsoft PowerPoint.")
        try:
            app.Visible = True
        except Exception as exc:
            visible_error = f"{type(exc).__name__}: {exc}"
        presentation, open_mode = open_presentation_for_check(app, ppt_path)
        inventory_rows = collect_origin_shapes(presentation, slide_filter)
        selected_rows = inventory_rows[:max_objects] if max_objects > 0 else inventory_rows
        if not inventory_only:
            for row in selected_rows:
                result_rows.append(
                    activate_shape(
                        app=app,
                        presentation=presentation,
                        row=row,
                        wait_seconds=wait_seconds,
                        expected_origin_path_contains=expected_origin_path_contains,
                    )
                )
    except Exception as exc:
        open_error = f"{type(exc).__name__}: {exc}"
    finally:
        if presentation is not None:
            try:
                presentation.Saved = True
            except Exception:
                pass
            try:
                presentation.Close()
            except Exception:
                pass
        if app is not None:
            if owns_app:
                try:
                    app.Quit()
                except Exception:
                    pass
        pythoncom.CoUninitialize()

    after_rows = process_snapshot()
    write_csv(out_dir / "process_after.csv", after_rows)
    write_csv(out_dir / "origin_ole_inventory.csv", inventory_rows)
    write_csv(out_dir / "origin_ole_activation_results.csv", result_rows)

    fail_count = sum(1 for row in result_rows if row.get("activation_status") == "fail")
    warning_count = sum(1 for row in result_rows if row.get("activation_status") == "warning")
    pass_count = sum(1 for row in result_rows if row.get("activation_status") == "pass")
    if open_error:
        overall = "fail"
    elif inventory_only:
        overall = "inventory_only"
    elif not inventory_rows:
        overall = "warning"
    elif fail_count:
        overall = "fail"
    elif warning_count:
        overall = "warning"
    else:
        overall = "pass"

    summary = {
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "ppt": str(ppt_path),
        "out_dir": str(out_dir),
        "slide_filter": sorted(slide_filter) if slide_filter else "all",
        "inventory_only": inventory_only,
        "dispatch_method": dispatch_method,
        "owns_powerpoint_app": owns_app,
        "open_mode": open_mode,
        "visible_error": visible_error,
        "open_error": open_error,
        "origin_ole_inventory_count": len(inventory_rows),
        "activation_attempt_count": len(result_rows),
        "activation_pass_count": pass_count,
        "activation_warning_count": warning_count,
        "activation_fail_count": fail_count,
        "overall_status": overall,
        "expected_origin_path_contains": expected_origin_path_contains,
        "process_before": str(out_dir / "process_before.csv"),
        "process_after": str(out_dir / "process_after.csv"),
        "inventory_csv": str(out_dir / "origin_ole_inventory.csv"),
        "activation_results_csv": str(out_dir / "origin_ole_activation_results.csv"),
    }
    write_json(out_dir / "ole_activation_summary.json", summary)
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate that embedded Origin OLE objects in a PowerPoint deck can be activated for editing."
    )
    parser.add_argument("ppt", type=Path, help="PPT/PPTX path to validate.")
    parser.add_argument("--out", type=Path, required=True, help="Output directory.")
    parser.add_argument("--slides", default=None, help="Slides to inspect, for example '1,3,5-6'. Default: all.")
    parser.add_argument("--wait-seconds", type=float, default=5.0, help="Wait after each OLE edit activation.")
    parser.add_argument("--max-objects", type=int, default=0, help="Maximum OLE objects to activate. 0 means all.")
    parser.add_argument(
        "--expected-origin-path-contains",
        default="",
        help="Optional substring expected in Origin64.exe path, e.g. 'Origin2026'.",
    )
    parser.add_argument("--inventory-only", action="store_true", help="Only inventory Origin OLE shapes; do not activate.")
    parser.add_argument("--warn-only", action="store_true", help="Return success even if activation fails.")
    args = parser.parse_args(argv)

    ppt_path = args.ppt.expanduser().resolve()
    if not ppt_path.exists():
        raise FileNotFoundError(ppt_path)
    out_dir = args.out.expanduser().resolve()
    summary = run_activation_check(
        ppt_path=ppt_path,
        out_dir=out_dir,
        slide_filter=parse_slide_spec(args.slides),
        wait_seconds=args.wait_seconds,
        max_objects=args.max_objects,
        expected_origin_path_contains=args.expected_origin_path_contains,
        inventory_only=args.inventory_only,
    )

    safe_print(f"OUT={out_dir}")
    safe_print(f"SUMMARY={out_dir / 'ole_activation_summary.json'}")
    safe_print(f"INVENTORY={out_dir / 'origin_ole_inventory.csv'}")
    safe_print(f"RESULTS={out_dir / 'origin_ole_activation_results.csv'}")
    safe_print(f"OVERALL_STATUS={summary['overall_status']}")
    safe_print(f"ORIGIN_OLE_INVENTORY={summary['origin_ole_inventory_count']}")
    safe_print(f"ACTIVATION_ATTEMPTS={summary['activation_attempt_count']}")
    safe_print(f"ACTIVATION_FAILS={summary['activation_fail_count']}")

    if summary["overall_status"] == "fail" and not args.warn_only:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
