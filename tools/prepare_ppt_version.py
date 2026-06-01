from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


def safe_print(message: str) -> None:
    try:
        print(message)
    except UnicodeEncodeError:
        sys.stdout.buffer.write((message + "\n").encode("utf-8", errors="replace"))


def sanitize_suffix(value: str) -> str:
    cleaned = re.sub(r"[^\w\u4e00-\u9fff.-]+", "_", value.strip(), flags=re.UNICODE)
    cleaned = cleaned.strip("._-")
    return cleaned or "new_version"


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    stem = path.stem
    suffix = path.suffix
    for idx in range(2, 1000):
        candidate = path.with_name(f"{stem}_v{idx}{suffix}")
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"Could not create a unique output path for {path}")


def default_output_path(source: Path, suffix: str, out_dir: Path | None, date_tag: str) -> Path:
    target_dir = out_dir if out_dir is not None else source.parent
    target_name = f"{source.stem}_{sanitize_suffix(suffix)}_{date_tag}{source.suffix}"
    return unique_path(target_dir / target_name)


def open_file(path: Path) -> None:
    if sys.platform.startswith("win"):
        subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                "& { param($p) Start-Process -FilePath $p }",
                str(path),
            ],
            check=True,
        )
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])


def write_version_record(record_path: Path, record: dict[str, Any]) -> None:
    record_path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Create a non-overwriting new PPT/PPTX version and optionally open it."
    )
    parser.add_argument("source", type=Path, help="Source PPT/PPTX path.")
    parser.add_argument("--suffix", required=True, help="Descriptive suffix for the new version.")
    parser.add_argument("--out-dir", type=Path, default=None, help="Output directory. Default: source directory.")
    parser.add_argument("--open", action="store_true", help="Open the new PPT/PPTX after creation.")
    parser.add_argument(
        "--date-tag",
        default=datetime.now().strftime("%Y%m%d"),
        help="Date tag for the output filename. Default: today as YYYYMMDD.",
    )
    args = parser.parse_args(argv)

    source = args.source.expanduser().resolve()
    if not source.exists():
        raise FileNotFoundError(source)
    if source.suffix.lower() not in {".ppt", ".pptx", ".pptm"}:
        raise RuntimeError(f"Source is not a PowerPoint file: {source}")

    out_dir = args.out_dir.expanduser().resolve() if args.out_dir is not None else None
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)
    output = default_output_path(source, args.suffix, out_dir, args.date_tag).resolve()
    if output == source:
        raise RuntimeError("Refusing to overwrite source PPT.")

    shutil.copy2(source, output)
    opened = False
    if args.open:
        open_file(output)
        opened = True

    record = {
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "source": str(source),
        "output": str(output),
        "suffix": args.suffix,
        "date_tag": args.date_tag,
        "opened": opened,
        "rule": "new PPT version created without overwriting source",
    }
    record_path = output.with_suffix(output.suffix + ".version_record.json")
    write_version_record(record_path, record)

    safe_print(f"SOURCE={source}")
    safe_print(f"OUTPUT={output}")
    safe_print(f"VERSION_RECORD={record_path}")
    safe_print(f"OPENED={opened}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
