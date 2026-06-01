from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import originpro as op
except ImportError as exc:  # pragma: no cover - environment dependent
    raise SystemExit("Missing originpro. Run this in an environment with OriginPro automation.") from exc


def safe_print(message: str) -> None:
    try:
        print(message)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((message + "\n").encode("utf-8", errors="replace"))


def safe_name(value: str) -> str:
    cleaned = re.sub(r"[^\w.-]+", "_", value.strip(), flags=re.UNICODE)
    cleaned = cleaned.strip("._-")
    return cleaned or "unnamed"


def finite_float(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def numeric_values(values: list[Any]) -> list[float]:
    out: list[float] = []
    for value in values:
        parsed = finite_float(value)
        if parsed is not None:
            out.append(parsed)
    return out


def excel_col_to_index(label: str) -> int | None:
    label = label.strip().upper()
    if not label or not re.fullmatch(r"[A-Z]+", label):
        return None
    value = 0
    for char in label:
        value = value * 26 + (ord(char) - ord("A") + 1)
    return value - 1


def index_to_excel_col(index: int) -> str:
    if index < 0:
        return ""
    chars: list[str] = []
    value = index + 1
    while value:
        value, rem = divmod(value - 1, 26)
        chars.append(chr(ord("A") + rem))
    return "".join(reversed(chars))


def paired_values(xs: list[Any], ys: list[Any]) -> tuple[list[float], list[float]]:
    out_x: list[float] = []
    out_y: list[float] = []
    for x_raw, y_raw in zip(xs, ys):
        x = finite_float(x_raw)
        y = finite_float(y_raw)
        if x is not None and y is not None:
            out_x.append(x)
            out_y.append(y)
    return out_x, out_y


def try_label(sheet: Any, col: int, label_type: str) -> str:
    try:
        value = sheet.get_label(col, label_type)
        return "" if value is None else str(value)
    except Exception:
        return ""


def try_prop(value: Any, default: Any = "") -> Any:
    try:
        return value() if callable(value) else value
    except Exception:
        return default


def try_attr(obj: Any, attr: str, default: Any = "") -> Any:
    try:
        return getattr(obj, attr)
    except Exception:
        return default


def workbook_name(workbook: Any) -> str:
    return str(getattr(workbook, "name", ""))


def page_long_name(page: Any) -> str:
    try:
        return str(page.long_name)
    except Exception:
        return ""


def audit_sheet_columns(
    opju_path: Path,
    workbook: Any,
    sheet: Any,
    sheet_index: int,
    max_columns: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    workbook_label = workbook_name(workbook)
    sheet_label = str(getattr(sheet, "name", f"sheet_{sheet_index}"))
    cols = int(getattr(sheet, "cols", 0) or 0)
    rows = int(getattr(sheet, "rows", 0) or 0)
    shape_rows = ""
    try:
        shape_rows = int(getattr(sheet, "shape", ("", ""))[0] or 0)
    except Exception:
        shape_rows = ""
    limit = cols if max_columns <= 0 else min(cols, max_columns)

    column_rows: list[dict[str, Any]] = []
    cached_cols: dict[int, list[Any]] = {}
    for col in range(limit):
        values = list(sheet.to_list(col))
        cached_cols[col] = values
        nums = numeric_values(values)
        column_rows.append(
            {
                "opju": str(opju_path),
                "workbook": workbook_label,
                "workbook_long_name": page_long_name(workbook),
                "sheet": sheet_label,
                "sheet_index": sheet_index,
                "rows": rows,
                "shape_rows": shape_rows,
                "cols": cols,
                "column_index": col,
                "short_name": try_label(sheet, col, "G") or index_to_excel_col(col),
                "long_name": try_label(sheet, col, "L"),
                "unit": try_label(sheet, col, "U"),
                "comment": try_label(sheet, col, "C"),
                "total_values": len(values),
                "numeric_count": len(nums),
                "blank_or_text_count": len(values) - len(nums),
                "numeric_min": min(nums) if nums else "",
                "numeric_max": max(nums) if nums else "",
                "first_numeric": nums[0] if nums else "",
                "last_numeric": nums[-1] if nums else "",
            }
        )

    pair_rows: list[dict[str, Any]] = []
    for x_col in range(0, limit - 1, 2):
        y_col = x_col + 1
        xs, ys = paired_values(cached_cols[x_col], cached_cols[y_col])
        x_decreases = sum(1 for idx in range(1, len(xs)) if xs[idx] < xs[idx - 1]) if xs else ""
        large_x_jumps = (
            sum(1 for idx in range(1, len(xs)) if abs(xs[idx] - xs[idx - 1]) > 0.25) if xs else ""
        )
        pair_rows.append(
            {
                "opju": str(opju_path),
                "workbook": workbook_label,
                "sheet": sheet_label,
                "sheet_index": sheet_index,
                "x_column_index": x_col,
                "y_column_index": y_col,
                "x_short_name": try_label(sheet, x_col, "G") or index_to_excel_col(x_col),
                "y_short_name": try_label(sheet, y_col, "G") or index_to_excel_col(y_col),
                "x_long_name": try_label(sheet, x_col, "L"),
                "y_long_name": try_label(sheet, y_col, "L"),
                "paired_numeric_count": len(xs),
                "pair_status": "has_numeric_data" if xs else "no_numeric_data",
                "x_min": min(xs) if xs else "",
                "x_max": max(xs) if xs else "",
                "y_min": min(ys) if ys else "",
                "y_max": max(ys) if ys else "",
                "x_first": xs[0] if xs else "",
                "x_last": xs[-1] if xs else "",
                "y_first": ys[0] if ys else "",
                "y_last": ys[-1] if ys else "",
                "x_decrease_steps": x_decreases,
                "large_x_jumps_gt_0p25": large_x_jumps,
            }
        )
    return column_rows, pair_rows


def parse_plot_source(plot_name: str) -> tuple[str, int | None, str]:
    match = re.match(r"^(?P<book>.+)_(?P<col>[A-Z]+)$", plot_name.strip())
    if not match:
        return "", None, ""
    return match.group("book"), excel_col_to_index(match.group("col")), match.group("col")


def audit_graph_plots(
    opju_path: Path,
    graph: Any,
    column_stats: dict[tuple[str, int, int], dict[str, Any]],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    graph_label = str(getattr(graph, "name", ""))
    try:
        layers = list(graph)
    except Exception:
        layers = []

    for layer_index, layer in enumerate(layers):
        try:
            plots = layer.plot_list()
        except Exception:
            plots = []
        for plot_index, plot in enumerate(plots):
            plot_name = str(getattr(plot, "name", ""))
            book, y_col_index, y_col_label = parse_plot_source(plot_name)
            x_col_index = y_col_index - 1 if y_col_index is not None and y_col_index > 0 else None
            y_stats = column_stats.get((book, 0, y_col_index)) if y_col_index is not None else None
            x_stats = column_stats.get((book, 0, x_col_index)) if x_col_index is not None else None
            x_numeric = int(x_stats.get("numeric_count", 0) or 0) if x_stats else 0
            y_numeric = int(y_stats.get("numeric_count", 0) or 0) if y_stats else 0
            if y_col_index is None:
                data_status = "unparsed_plot_name"
            elif not y_stats:
                data_status = "source_column_not_audited"
            elif x_numeric > 0 and y_numeric > 0:
                data_status = "has_numeric_source"
            else:
                data_status = "no_numeric_source"
            rows.append(
                {
                    "opju": str(opju_path),
                    "graph": graph_label,
                    "layer_index": layer_index,
                    "plot_index": plot_index,
                    "plot_name": plot_name,
                    "source_book": book,
                    "inferred_x_column_index": x_col_index if x_col_index is not None else "",
                    "inferred_y_column_index": y_col_index if y_col_index is not None else "",
                    "inferred_x_short_name": index_to_excel_col(x_col_index) if x_col_index is not None else "",
                    "inferred_y_short_name": y_col_label,
                    "x_long_name": x_stats.get("long_name", "") if x_stats else "",
                    "y_long_name": y_stats.get("long_name", "") if y_stats else "",
                    "x_numeric_count": x_numeric,
                    "y_numeric_count": y_numeric,
                    "data_status": data_status,
                    "color_rgb": try_prop(try_attr(plot, "color")),
                    "symbol_kind": try_prop(try_attr(plot, "symbol_kind")),
                    "symbol_size": try_prop(try_attr(plot, "symbol_size")),
                    "group": try_prop(try_attr(plot, "group")),
                    "transparency": try_prop(try_attr(plot, "transparency")),
                }
            )
    return rows


def export_graph_preview(opju_path: Path, graph: Any, out_dir: Path, width: int) -> str:
    target = out_dir / f"{safe_name(opju_path.stem)}_{safe_name(str(getattr(graph, 'name', 'graph')))}.png"
    if target.exists():
        target.unlink()
    graph.save_fig(str(target), width=width)
    return str(target)


def audit_opju(opju_path: Path, out_dir: Path, max_columns: int, export_figures: bool, figure_width: int) -> dict[str, Any]:
    if not opju_path.exists():
        raise FileNotFoundError(opju_path)

    try:
        op.set_show(False)
    except Exception:
        pass

    op.new(asksave=False)
    if not op.open(str(opju_path), readonly=True, asksave=False):
        raise RuntimeError(f"Origin failed to open {opju_path}")

    figure_dir = out_dir / "graph_previews"
    if export_figures:
        figure_dir.mkdir(parents=True, exist_ok=True)

    workbook_rows: list[dict[str, Any]] = []
    column_rows: list[dict[str, Any]] = []
    pair_rows: list[dict[str, Any]] = []
    graph_rows: list[dict[str, Any]] = []
    graph_plot_rows: list[dict[str, Any]] = []
    issue_rows: list[dict[str, Any]] = []

    for workbook in op.pages("w"):
        workbook_label = workbook_name(workbook)
        try:
            sheet_count = len(workbook)
        except Exception:
            sheet_count = 1
        workbook_rows.append(
            {
                "opju": str(opju_path),
                "workbook": workbook_label,
                "workbook_long_name": page_long_name(workbook),
                "sheet_count": sheet_count,
            }
        )
        for sheet_index in range(sheet_count):
            sheet = workbook[sheet_index]
            sheet_label = str(getattr(sheet, "name", f"sheet_{sheet_index}"))
            cols, pairs = audit_sheet_columns(opju_path, workbook, sheet, sheet_index, max_columns)
            column_rows.extend(cols)
            pair_rows.extend(pairs)
            numeric_cols = sum(1 for row in cols if int(row.get("numeric_count", 0) or 0) > 0)
            shape_rows = cols[0].get("shape_rows", "") if cols else ""
            if cols and numeric_cols == 0:
                issue_rows.append(
                    {
                        "opju": str(opju_path),
                        "level": "warning",
                        "scope": "worksheet",
                        "object": f"{workbook_label}/{sheet_label}",
                        "message": (
                            f"No numeric worksheet data found; rows={cols[0].get('rows', '')}, "
                            f"shape_rows={shape_rows}, cols={len(cols)}."
                        ),
                    }
                )

    column_stats = {
        (str(row.get("workbook", "")), int(row.get("sheet_index", 0) or 0), int(row.get("column_index", 0) or 0)): row
        for row in column_rows
    }

    for graph in op.pages("g"):
        plot_rows = audit_graph_plots(opju_path, graph, column_stats)
        graph_plot_rows.extend(plot_rows)
        preview = ""
        if export_figures:
            try:
                preview = export_graph_preview(opju_path, graph, figure_dir, figure_width)
            except Exception as exc:
                preview = f"EXPORT_FAILED: {type(exc).__name__}"
        try:
            layer_count = len(graph)
        except Exception:
            layer_count = ""
        graph_rows.append(
            {
                "opju": str(opju_path),
                "graph": str(getattr(graph, "name", "")),
                "graph_long_name": page_long_name(graph),
                "layer_count": layer_count,
                "plot_count": len(plot_rows),
                "plots_with_numeric_source": sum(
                    1 for row in plot_rows if row.get("data_status") == "has_numeric_source"
                ),
                "preview": preview,
            }
        )
        if plot_rows and not any(row.get("data_status") == "has_numeric_source" for row in plot_rows):
            issue_rows.append(
                {
                    "opju": str(opju_path),
                    "level": "warning",
                    "scope": "graph",
                    "object": str(getattr(graph, "name", "")),
                    "message": "Graph contains plot objects, but none have numeric worksheet source data.",
                }
            )

    return {
        "opju": str(opju_path),
        "workbooks": workbook_rows,
        "columns": column_rows,
        "pairs": pair_rows,
        "graphs": graph_rows,
        "graph_plots": graph_plot_rows,
        "issues": issue_rows,
    }


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
    parser = argparse.ArgumentParser(description="Audit Origin OPJU workbook data and graph previews.")
    parser.add_argument("opju", nargs="+", type=Path, help="OPJU file(s) to audit.")
    parser.add_argument("--out", type=Path, required=True, help="Output directory.")
    parser.add_argument("--max-columns", type=int, default=0, help="Columns per sheet to audit. 0 means all.")
    parser.add_argument("--no-figures", action="store_true", help="Do not export graph preview PNG files.")
    parser.add_argument("--figure-width", type=int, default=1600)
    args = parser.parse_args(argv)

    out_dir = args.out.expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    all_workbooks: list[dict[str, Any]] = []
    all_columns: list[dict[str, Any]] = []
    all_pairs: list[dict[str, Any]] = []
    all_graphs: list[dict[str, Any]] = []
    all_graph_plots: list[dict[str, Any]] = []
    all_issues: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []

    try:
        for raw_path in args.opju:
            opju_path = raw_path.expanduser().resolve()
            try:
                result = audit_opju(
                    opju_path=opju_path,
                    out_dir=out_dir,
                    max_columns=args.max_columns,
                    export_figures=not args.no_figures,
                    figure_width=args.figure_width,
                )
                all_workbooks.extend(result["workbooks"])
                all_columns.extend(result["columns"])
                all_pairs.extend(result["pairs"])
                all_graphs.extend(result["graphs"])
                all_graph_plots.extend(result["graph_plots"])
                all_issues.extend(result["issues"])
            except Exception as exc:
                errors.append({"opju": str(opju_path), "error": type(exc).__name__, "message": str(exc)})
    finally:
        try:
            op.exit()
        except Exception:
            pass

    write_csv(out_dir / "opju_workbooks.csv", all_workbooks)
    write_csv(out_dir / "opju_columns.csv", all_columns)
    write_csv(out_dir / "opju_xy_pairs.csv", all_pairs)
    write_csv(out_dir / "opju_graphs.csv", all_graphs)
    write_csv(out_dir / "opju_graph_plots.csv", all_graph_plots)
    write_csv(out_dir / "opju_audit_issues.csv", all_issues)
    write_csv(out_dir / "opju_audit_errors.csv", errors)

    summary = {
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "opju_count": len(args.opju),
        "workbook_count": len(all_workbooks),
        "column_count": len(all_columns),
        "xy_pair_count": len(all_pairs),
        "xy_pair_with_data_count": sum(1 for row in all_pairs if row.get("pair_status") == "has_numeric_data"),
        "graph_count": len(all_graphs),
        "graph_plot_count": len(all_graph_plots),
        "graph_plot_with_numeric_source_count": sum(
            1 for row in all_graph_plots if row.get("data_status") == "has_numeric_source"
        ),
        "issue_count": len(all_issues),
        "error_count": len(errors),
        "out_dir": str(out_dir),
    }
    (out_dir / "opju_audit_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    safe_print(f"OUT={out_dir}")
    safe_print(f"SUMMARY={out_dir / 'opju_audit_summary.json'}")
    safe_print(f"WORKBOOKS={out_dir / 'opju_workbooks.csv'}")
    safe_print(f"COLUMNS={out_dir / 'opju_columns.csv'}")
    safe_print(f"XY_PAIRS={out_dir / 'opju_xy_pairs.csv'}")
    safe_print(f"GRAPHS={out_dir / 'opju_graphs.csv'}")
    safe_print(f"GRAPH_PLOTS={out_dir / 'opju_graph_plots.csv'}")
    safe_print(f"ISSUES={len(all_issues)}")
    safe_print(f"ERRORS={len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
