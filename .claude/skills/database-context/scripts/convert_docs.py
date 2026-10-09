#!/usr/bin/env python3
"""Convert documentation under a data folder to Markdown and write an inventory.

Usage: python convert_docs.py [DATA_DIR] [OUT_DIR]
  DATA_DIR  default: data
  OUT_DIR   default: <DATA_DIR>/_converted   (one .md per source + _inventory.md)

Privacy rule: only documentation is converted. Tabular data files (.csv, .tsv, .parquet,
.sas7bdat, .dta, ...) are listed by name and size and are NEVER opened, because they may
hold patient-level rows. Excel workbooks are converted only up to MAX_XLSX_ROWS rows per
sheet and are flagged when they look like data rather than a dictionary.

Works with the standard library alone for .md/.txt; uses pypdf, python-docx and openpyxl
when installed and says so in the inventory when one is missing.
"""
import os
import sys
import re
import csv
import io
from pathlib import Path

DOC_EXT = {".md", ".markdown", ".txt", ".rst", ".pdf", ".docx", ".xlsx", ".xlsm", ".html", ".htm"}
DATA_EXT = {".csv", ".tsv", ".parquet", ".feather", ".sas7bdat", ".dta", ".rds", ".rdata",
            ".db", ".sqlite", ".json", ".jsonl", ".gz", ".zip"}
SKIP_DIRS = {"_converted", ".git", "__pycache__", "node_modules"}
MAX_XLSX_ROWS = 500
# A small CSV that is itself documentation (manifest, dictionary, codebook) may be converted
# when its name says so; everything else is treated as data.
DOC_CSV_HINT = re.compile(r"(dictionary|codebook|schema|manifest|datadict|variables|codelist|code_list|metadata_)", re.I)


def md_table(rows):
    rows = [[("" if c is None else str(c)).replace("\n", " ").replace("|", "\\|") for c in r] for r in rows]
    if not rows:
        return ""
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    out = ["| " + " | ".join(rows[0]) + " |", "|" + "---|" * width]
    out += ["| " + " | ".join(r) + " |" for r in rows[1:]]
    return "\n".join(out)


def convert_text(p):
    return p.read_text(encoding="utf-8", errors="replace"), None


def convert_html(p):
    t = p.read_text(encoding="utf-8", errors="replace")
    t = re.sub(r"(?is)<(script|style).*?</\1>", "", t)
    t = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</h\d>|</tr>", "\n", t)
    t = re.sub(r"<[^>]+>", " ", t)
    return re.sub(r"\n\s*\n+", "\n\n", t), "html stripped to text; tables flattened"


def convert_pdf(p):
    try:
        from pypdf import PdfReader
    except ImportError:
        return None, "pypdf not installed (pip install pypdf)"
    r = PdfReader(str(p))
    parts = []
    for i, page in enumerate(r.pages, 1):
        parts.append(f"\n\n<!-- page {i} -->\n\n" + (page.extract_text() or ""))
    text = "".join(parts)
    note = None
    if len(text.strip()) < 200 * max(1, len(r.pages)) * 0.1:
        note = "very little text extracted; likely a scanned PDF, needs OCR"
    return text, note or "PDF text extraction loses tables and layout; verify tables against the source"


def convert_docx(p):
    try:
        import docx
    except ImportError:
        return None, "python-docx not installed (pip install python-docx)"
    d = docx.Document(str(p))
    out = []
    for para in d.paragraphs:
        t = para.text.strip()
        if not t:
            continue
        m = re.match(r"Heading (\d)", para.style.name or "")
        out.append(("#" * int(m.group(1)) + " " if m else "") + t)
    for i, tbl in enumerate(d.tables, 1):
        out.append(f"\n**Table {i}**\n\n" + md_table([[c.text for c in row.cells] for row in tbl.rows]))
    return "\n\n".join(out), "tables appended at end of document, original position lost"


def convert_xlsx(p):
    try:
        import openpyxl
    except ImportError:
        return None, "openpyxl not installed (pip install openpyxl)"
    wb = openpyxl.load_workbook(str(p), read_only=True, data_only=True)
    out, notes = [], []
    for ws in wb.worksheets:
        rows = []
        for i, row in enumerate(ws.iter_rows(values_only=True)):
            if i >= MAX_XLSX_ROWS:
                notes.append(f"sheet '{ws.title}' truncated at {MAX_XLSX_ROWS} rows; "
                             "if it is a dictionary, check the rest; if it is data, do not use it")
                break
            rows.append(row)
        out.append(f"## Sheet: {ws.title}\n\n" + md_table(rows))
    return "\n\n".join(out), "; ".join(notes) or None


def convert_doc_csv(p):
    raw = p.read_text(encoding="utf-8", errors="replace")
    rows = list(csv.reader(io.StringIO(raw)))[:MAX_XLSX_ROWS]
    return md_table(rows), "documentation-style CSV converted (capped at %d rows)" % MAX_XLSX_ROWS


CONVERTERS = {".md": convert_text, ".markdown": convert_text, ".txt": convert_text, ".rst": convert_text,
              ".html": convert_html, ".htm": convert_html, ".pdf": convert_pdf, ".docx": convert_docx,
              ".xlsx": convert_xlsx, ".xlsm": convert_xlsx}


def main():
    data = Path(sys.argv[1] if len(sys.argv) > 1 else "data").resolve()
    out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else data / "_converted"
    if not data.is_dir():
        sys.exit(f"Data folder not found: {data}")
    out.mkdir(parents=True, exist_ok=True)
    converted, failed, data_files = [], [], []
    for root, dirs, files in os.walk(data):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in sorted(files):
            p = Path(root) / f
            rel = p.relative_to(data)
            ext = p.suffix.lower()
            if ext in DOC_EXT:
                conv = CONVERTERS[ext]
            elif ext == ".csv" and DOC_CSV_HINT.search(p.stem):
                conv = convert_doc_csv
            elif ext in DATA_EXT or ext == ".csv":
                data_files.append((rel, p.stat().st_size))
                continue
            else:
                continue
            try:
                text, note = conv(p)
            except Exception as e:  # keep going: one bad file must not stop the run
                failed.append((rel, f"{type(e).__name__}: {e}"))
                continue
            if text is None:
                failed.append((rel, note))
                continue
            target = out / (str(rel).replace(os.sep, "__") + ".md")
            target.write_text(f"<!-- source: {rel.as_posix()} -->\n\n{text}", encoding="utf-8")
            converted.append((rel, target.name, len(text), note))

    lines = ["# Source inventory", "", f"Data folder: `{data}`", "",
             f"## Converted documentation ({len(converted)})", "",
             "| Source | Converted file | Chars | Note |", "|---|---|---|---|"]
    lines += [f"| {r.as_posix()} | {t} | {n} | {note or ''} |" for r, t, n, note in converted]
    lines += ["", f"## Not converted ({len(failed)})", "", "| Source | Reason |", "|---|---|"]
    lines += [f"| {r.as_posix()} | {why} |" for r, why in failed]
    lines += ["", f"## Data files, listed only, never opened ({len(data_files)})", "",
              "| File | Size (bytes) |", "|---|---|"]
    lines += [f"| {r.as_posix()} | {s} |" for r, s in data_files]
    (out / "_inventory.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"converted={len(converted)} failed={len(failed)} data_files_skipped={len(data_files)} -> {out}")
    for r, why in failed:
        print(f"  FAILED {r.as_posix()}: {why}")


if __name__ == "__main__":
    main()
