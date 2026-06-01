#!/usr/bin/env python3
"""
Batch import data into Origin, create a graph, and export an image.

Example:
    python origin_batch_plot.py ^
      --input "C:\\data\\demo.csv" ^
      --x-col 0 ^
      --y-col 1 ^
      --output "C:\\data\\demo.png" ^
      --template "scatter" ^
      --show-origin
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _safe_write(stream, text: str) -> None:
    data = (text + "\n").encode("utf-8", errors="backslashreplace")
    buffer = getattr(stream, "buffer", None)
    if buffer is not None:
        buffer.write(data)
        buffer.flush()
        return
    stream.write(data.decode("utf-8", errors="replace"))
    stream.flush()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Use OriginPro (COM-based) to import data, plot, and export."
    )
    parser.add_argument(
        "--input",
        required=True,
        help="Input data file path. CSV/Excel and other connector-supported files.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output figure path, e.g. C:\\out\\plot.png or .svg/.emf.",
    )
    parser.add_argument(
        "--x-col",
        type=int,
        default=0,
        help="Zero-based column index for X (default: 0).",
    )
    parser.add_argument(
        "--y-col",
        type=int,
        default=1,
        help="Zero-based column index for Y (default: 1).",
    )
    parser.add_argument(
        "--plot-type",
        default="?",
        help="Plot type code for add_plot: l/s/y/c/? (default: ?).",
    )
    parser.add_argument(
        "--template",
        default="",
        help="Origin graph template name/path, e.g. scatter, line, origin.otp.",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=1200,
        help="Export width in pixels (default: 1200).",
    )
    parser.add_argument(
        "--show-origin",
        action="store_true",
        help="Show Origin UI while running (useful for debugging).",
    )
    parser.add_argument(
        "--keep-open",
        action="store_true",
        help="Keep Origin open after script finishes.",
    )
    return parser.parse_args()


def _validate_columns(x_col: int, y_col: int) -> None:
    if x_col < 0 or y_col < 0:
        raise ValueError("x-col and y-col must be >= 0 (zero-based).")
    if x_col == y_col:
        raise ValueError("x-col and y-col cannot be the same column.")


def main() -> int:
    args = _parse_args()
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    _validate_columns(args.x_col, args.y_col)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        import originpro as op
    except ImportError as exc:
        raise RuntimeError(
            "originpro is not installed. Run: pip install originpro"
        ) from exc

    if op.oext and args.show_origin:
        op.set_show(True)

    try:
        wks = op.new_sheet("w")
        wks.from_file(str(input_path), keep_DC=False)

        graph = op.new_graph(template=args.template) if args.template else op.new_graph()
        layer = graph[0]
        layer.add_plot(
            wks,
            coly=args.y_col,
            colx=args.x_col,
            type=args.plot_type,
        )
        layer.rescale()

        exported = graph.save_fig(str(output_path), width=args.width)
        if not exported:
            raise RuntimeError(
                "Origin reported an empty export path. Check template/output settings."
            )

        _safe_write(sys.stdout, f"Exported: {exported}")
    finally:
        if op.oext and not args.keep_open:
            op.exit()

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as err:  # noqa: BLE001
        _safe_write(sys.stderr, f"[ERROR] {err}")
        raise SystemExit(1)
