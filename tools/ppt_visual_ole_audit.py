from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import pythoncom
    import win32com.client
except ImportError as exc:  # pragma: no cover - environment dependent
    raise SystemExit(
        "Missing pywin32. Install pywin32 or run this script in the Codex/WPS environment."
    ) from exc


DEFAULT_WIDTH = 1600
DEFAULT_HEIGHT = 900
DEFAULT_CONTACT_COLUMNS = 3
DEFAULT_THUMB_WIDTH = 420


def safe_print(message: str) -> None:
    try:
        print(message)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((message + "\n").encode("utf-8", errors="replace"))


def parse_slide_spec(value: str | None) -> set[int] | None:
    if not value:
        return None
    slides: set[int] = set()
    for chunk in value.split(","):
        part = chunk.strip()
        if not part:
            continue
        if "-" in part:
            start_raw, end_raw = part.split("-", 1)
            start = int(start_raw)
            end = int(end_raw)
            if end < start:
                raise ValueError(f"Bad slide range: {part}")
            slides.update(range(start, end + 1))
        else:
            slides.add(int(part))
    return slides


def ensure_out_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def try_set_visible(app: Any, visible: bool) -> None:
    try:
        app.Visible = visible
    except Exception:
        pass


def dispatch_presentation_app(prefer: str, allow_fallback: bool = False) -> tuple[Any, str]:
    requested = "PowerPoint.Application" if prefer == "powerpoint" else "kwpp.Application"
    fallback = "kwpp.Application" if prefer == "powerpoint" else "PowerPoint.Application"
    progids = [requested]
    if allow_fallback:
        progids.append(fallback)
    errors: list[str] = []
    for progid in progids:
        try:
            return win32com.client.DispatchEx(progid), progid
        except Exception as exc:
            errors.append(f"{progid}: {type(exc).__name__}")
    raise RuntimeError("Unable to start requested presentation COM app. " + "; ".join(errors))


def shape_text(shape: Any) -> str:
    try:
        if shape.HasTextFrame and shape.TextFrame.HasText:
            return str(shape.TextFrame.TextRange.Text).replace("\r", " | ")
    except Exception:
        return ""
    return ""


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


def safe_attr(obj: Any, name: str, default: Any = "") -> Any:
    try:
        return getattr(obj, name, default)
    except Exception:
        return default


def audit_shape(slide_index: int, shape_index: int, shape: Any) -> dict[str, Any]:
    progid = shape_progid(shape)
    text = shape_text(shape)
    return {
        "slide": slide_index,
        "shape_index": shape_index,
        "name": str(safe_attr(shape, "Name", "")),
        "type": int(safe_attr(shape, "Type", -999) or -999),
        "progid": progid,
        "is_origin_ole": "Origin" in progid,
        "left": safe_float(safe_attr(shape, "Left", None)),
        "top": safe_float(safe_attr(shape, "Top", None)),
        "width": safe_float(safe_attr(shape, "Width", None)),
        "height": safe_float(safe_attr(shape, "Height", None)),
        "text_preview": text[:200],
    }


def export_slide(slide: Any, target: Path, width: int, height: int) -> None:
    if target.exists():
        target.unlink()
    slide.Export(str(target), "PNG", width, height)


def make_contact_sheet(
    screenshot_rows: list[dict[str, Any]],
    target: Path,
    columns: int,
    thumb_width: int,
) -> str:
    if not screenshot_rows:
        return ""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:  # pragma: no cover - optional dependency
        raise RuntimeError("Pillow is required to create a contact sheet.") from exc

    columns = max(1, columns)
    thumb_width = max(120, thumb_width)
    padding = 28
    label_height = 34

    thumbs: list[tuple[int, Image.Image]] = []
    for row in screenshot_rows:
        image_path = Path(str(row["path"]))
        with Image.open(image_path) as img:
            img = img.convert("RGB")
            ratio = thumb_width / img.width
            thumb_height = max(1, int(img.height * ratio))
            thumb = img.resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
            thumbs.append((int(row["slide"]), thumb))

    cell_width = thumb_width + padding * 2
    max_thumb_height = max(thumb.height for _, thumb in thumbs)
    cell_height = max_thumb_height + label_height + padding * 2
    rows = (len(thumbs) + columns - 1) // columns
    sheet = Image.new("RGB", (cell_width * columns, cell_height * rows), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 22)
    except Exception:
        font = ImageFont.load_default()

    for idx, (slide_index, thumb) in enumerate(thumbs):
        col = idx % columns
        row = idx // columns
        x0 = col * cell_width + padding
        y0 = row * cell_height + padding
        draw.text((x0, y0), f"Slide {slide_index}", fill="black", font=font)
        sheet.paste(thumb, (x0, y0 + label_height))
        draw.rectangle(
            [x0, y0 + label_height, x0 + thumb.width - 1, y0 + label_height + thumb.height - 1],
            outline=(180, 180, 180),
            width=1,
        )

    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.unlink()
    sheet.save(target)
    return str(target)


def audit_ppt(
    ppt_path: Path,
    out_dir: Path,
    slide_filter: set[int] | None,
    export_screenshots: bool,
    width: int,
    height: int,
    prefer_app: str,
    allow_app_fallback: bool = False,
    create_contact_sheet: bool = True,
    contact_columns: int = DEFAULT_CONTACT_COLUMNS,
    thumb_width: int = DEFAULT_THUMB_WIDTH,
) -> dict[str, Any]:
    if not ppt_path.exists():
        raise FileNotFoundError(ppt_path)

    out_dir = ensure_out_dir(out_dir)
    screenshot_dir = ensure_out_dir(out_dir / "screenshots") if export_screenshots else None
    shape_rows: list[dict[str, Any]] = []
    screenshot_rows: list[dict[str, Any]] = []

    pythoncom.CoInitialize()
    app = None
    presentation = None
    app_progid = ""
    try:
        app, app_progid = dispatch_presentation_app(prefer_app, allow_fallback=allow_app_fallback)
        try_set_visible(app, False)
        presentation = app.Presentations.Open(str(ppt_path), False, True, True)
        slide_count = int(presentation.Slides.Count)
        selected = slide_filter or set(range(1, slide_count + 1))

        for slide_index in range(1, slide_count + 1):
            slide = presentation.Slides(slide_index)
            if slide_index not in selected:
                continue
            for shape_index in range(1, int(slide.Shapes.Count) + 1):
                shape_rows.append(audit_shape(slide_index, shape_index, slide.Shapes(shape_index)))
            if screenshot_dir is not None:
                target = screenshot_dir / f"slide_{slide_index:02d}.png"
                export_slide(slide, target, width, height)
                screenshot_rows.append({"slide": slide_index, "path": str(target)})

        origin_counts: dict[str, int] = {}
        for row in shape_rows:
            if row["is_origin_ole"]:
                key = str(row["slide"])
                origin_counts[key] = origin_counts.get(key, 0) + 1
        contact_sheet = ""
        contact_sheet_error = ""
        if create_contact_sheet and screenshot_rows:
            try:
                contact_sheet = make_contact_sheet(
                    screenshot_rows=screenshot_rows,
                    target=out_dir / "slide_contact_sheet.png",
                    columns=contact_columns,
                    thumb_width=thumb_width,
                )
            except Exception as exc:
                contact_sheet_error = f"{type(exc).__name__}: {exc}"

        summary = {
            "ppt_path": str(ppt_path),
            "out_dir": str(out_dir),
            "app_progid": app_progid,
            "requested_app": prefer_app,
            "allow_app_fallback": allow_app_fallback,
            "fallback_used": (
                prefer_app == "powerpoint" and "PowerPoint" not in app_progid
            )
            or (prefer_app == "wps" and "kwpp" not in app_progid),
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "slide_count": slide_count,
            "audited_slides": sorted(selected),
            "screenshot_count": len(screenshot_rows),
            "shape_count": len(shape_rows),
            "origin_ole_total": sum(origin_counts.values()),
            "origin_ole_by_slide": origin_counts,
            "screenshots": screenshot_rows,
            "contact_sheet": contact_sheet,
            "contact_sheet_error": contact_sheet_error,
        }

        return {"summary": summary, "shapes": shape_rows}
    finally:
        if presentation is not None:
            try:
                presentation.Close()
            except Exception:
                pass
        if app is not None:
            try:
                app.Quit()
            except Exception:
                pass
        pythoncom.CoUninitialize()


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields = list(rows[0].keys())
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Export PPT screenshots and audit Origin OLE objects for scientific PowerPoint work."
    )
    parser.add_argument("ppt", type=Path, help="Input PPT/PPTX path.")
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Output directory. Default: <ppt stem>_qa_<timestamp> next to the PPT.",
    )
    parser.add_argument(
        "--slides",
        default=None,
        help="Slides to audit/export, for example '1,3,5-6'. Default: all slides.",
    )
    parser.add_argument(
        "--no-screenshots",
        action="store_true",
        help="Audit shapes and OLE objects without exporting slide PNG screenshots.",
    )
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH, help="Screenshot width in pixels.")
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT, help="Screenshot height in pixels.")
    parser.add_argument("--no-contact-sheet", action="store_true", help="Do not create slide_contact_sheet.png.")
    parser.add_argument("--contact-columns", type=int, default=DEFAULT_CONTACT_COLUMNS)
    parser.add_argument("--thumb-width", type=int, default=DEFAULT_THUMB_WIDTH)
    parser.add_argument(
        "--prefer-app",
        choices=["wps", "powerpoint"],
        default="powerpoint",
        help="COM app preference. Default: powerpoint.",
    )
    parser.add_argument(
        "--allow-app-fallback",
        action="store_true",
        help="Allow fallback to the other presentation app if the requested COM app fails.",
    )
    args = parser.parse_args(argv)

    ppt_path = args.ppt.expanduser().resolve()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = args.out
    if out_dir is None:
        out_dir = ppt_path.parent / f"{ppt_path.stem}_qa_{timestamp}"
    out_dir = out_dir.expanduser().resolve()
    slide_filter = parse_slide_spec(args.slides)

    result = audit_ppt(
        ppt_path=ppt_path,
        out_dir=out_dir,
        slide_filter=slide_filter,
        export_screenshots=not args.no_screenshots,
        width=args.width,
        height=args.height,
        prefer_app=args.prefer_app,
        allow_app_fallback=args.allow_app_fallback,
        create_contact_sheet=not args.no_contact_sheet,
        contact_columns=args.contact_columns,
        thumb_width=args.thumb_width,
    )

    ensure_out_dir(out_dir)
    summary_path = out_dir / "ppt_qa_summary.json"
    shapes_path = out_dir / "ppt_shape_audit.csv"
    summary_path.write_text(json.dumps(result["summary"], ensure_ascii=False, indent=2), encoding="utf-8")
    write_csv(shapes_path, result["shapes"])

    safe_print(f"QA_OUT={out_dir}")
    safe_print(f"SUMMARY={summary_path}")
    safe_print(f"SHAPES={shapes_path}")
    safe_print(f"APP={result['summary']['app_progid']}")
    safe_print(f"FALLBACK_USED={result['summary']['fallback_used']}")
    safe_print(f"SLIDES={result['summary']['slide_count']}")
    safe_print(f"SCREENSHOTS={result['summary']['screenshot_count']}")
    safe_print(f"CONTACT_SHEET={result['summary']['contact_sheet']}")
    if result["summary"]["contact_sheet_error"]:
        safe_print(f"CONTACT_SHEET_ERROR={result['summary']['contact_sheet_error']}")
    safe_print(f"ORIGIN_OLE_TOTAL={result['summary']['origin_ole_total']}")
    safe_print(f"ORIGIN_OLE_BY_SLIDE={json.dumps(result['summary']['origin_ole_by_slide'], ensure_ascii=False)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
