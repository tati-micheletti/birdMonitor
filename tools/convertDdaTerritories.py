#!/usr/bin/env python3
"""Convert the two DDA territory workbooks (raw, never modified) into plain csv copies, cell for cell, for the figure script (tools/makeResultFigures.R, section S9).

    python3 tools/convertDdaTerritories.py [--raw inputs/response/raw/territories] [--out inputs/response/processed/territories_csv]

Input : BirdStats_Visits2005-2024D.xlsx        -> dda_visits.csv  (Nummer, Jahr, Countdate, ROUTENCODE)
        BirdStats_Daten2005-2024D_alle.xlsx    -> dda_data.csv    (Nummer, Countdate, EURING, Reviere, Art deutsch, ROUTENCODE, Cov1)
Nothing is filtered, recoded or aggregated: every row and column of the single sheet is written as it is, dates as YYYY-MM-DD, empty cells as empty fields.
Only the Python standard library is used (an xlsx file is a zip file of xml files), so it runs on EVE without installing anything.
The sha256 of the inputs and of the outputs is printed, so that the copy can be shown to be a faithful conversion of a given workbook.
Checked against the same conversion made with openpyxl: the csv files are byte for byte identical.
"""
import argparse, csv, datetime, hashlib, os, re, sys, zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
RNS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
FILES = {"BirdStats_Visits2005-2024D.xlsx": "dda_visits.csv", "BirdStats_Daten2005-2024D_alle.xlsx": "dda_data.csv"}
BUILTIN_DATE_IDS = set(range(14, 23)) | {45, 46, 47}

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def col_index(ref):                                   # "AB12" -> 27 (zero based)
    letters = re.match(r"[A-Z]+", ref).group(0)
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n - 1

def is_date_code(code):                               # custom number format with date or time letters outside quotes and brackets
    code = re.sub(r'"[^"]*"|\[[^\]]*\]|\\.', "", code.lower())
    return any(ch in code for ch in "ymdhs")

def read_shared_strings(z):
    if "xl/sharedStrings.xml" not in z.namelist():
        return []
    out = []
    for _, el in ET.iterparse(z.open("xl/sharedStrings.xml")):
        if el.tag == NS + "si":
            out.append("".join(t.text or "" for t in el.iter(NS + "t")))
            el.clear()
    return out

def read_date_styles(z):                              # set of cell style indices (attribute s) whose number format is a date
    root = ET.parse(z.open("xl/styles.xml")).getroot()
    custom = {int(n.get("numFmtId")): n.get("formatCode") for n in root.iter(NS + "numFmt")}
    xfs = root.find(NS + "cellXfs")
    dates = set()
    for i, xf in enumerate(xfs.findall(NS + "xf")):
        fid = int(xf.get("numFmtId", "0"))
        if fid in BUILTIN_DATE_IDS or (fid in custom and is_date_code(custom[fid])):
            dates.add(i)
    return dates

def first_sheet_path(z):
    wb = ET.parse(z.open("xl/workbook.xml")).getroot()
    sheets = wb.find(NS + "sheets").findall(NS + "sheet")
    assert len(sheets) == 1, "expected one sheet, found %d" % len(sheets)
    rid = sheets[0].get(RNS + "id")
    rels = ET.parse(z.open("xl/_rels/workbook.xml.rels")).getroot()
    for r in rels:
        if r.get("Id") == rid:
            t = r.get("Target")
            return t.lstrip("/") if t.startswith("/") else "xl/" + t
    raise RuntimeError("sheet relationship not found")

def cell_value(c, shared, date_styles):               # same rules as openpyxl: integer if no '.', 'E' or 'e', else float; date styles -> date
    t = c.get("t"); v = c.find(NS + "v")
    if t == "inlineStr":
        return "".join(x.text or "" for x in c.iter(NS + "t"))
    if v is None or v.text is None:
        return ""
    if t == "s":
        return shared[int(v.text)]
    if t in ("str", "e"):
        return v.text
    if t == "b":
        return "True" if v.text == "1" else "False"
    num = float(v.text) if re.search(r"[.eE]", v.text) else int(v.text)
    if int(c.get("s", "0")) in date_styles:
        return (datetime.datetime(1899, 12, 30) + datetime.timedelta(days=float(num))).date().isoformat()
    return num

def convert(src, dst):
    with zipfile.ZipFile(src) as z:
        shared = read_shared_strings(z); date_styles = read_date_styles(z); sheet = first_sheet_path(z)
        ncol = None
        for _, el in ET.iterparse(z.open(sheet), events=("start",)):          # width of the sheet from its dimension, as openpyxl pads rows to it
            if el.tag == NS + "dimension":
                ncol = col_index(el.get("ref").split(":")[-1]) + 1
                break
        n = 0; last = 0
        with open(dst, "w", newline="", encoding="utf-8") as f:                   # csv module default line ending (CRLF), as in the copies already used
            w = csv.writer(f)
            for _, row in ET.iterparse(z.open(sheet)):
                if row.tag != NS + "row":
                    continue
                r = int(row.get("r", last + 1))
                while last + 1 < r:                                              # rows missing from the file are empty rows
                    w.writerow([""] * (ncol or 0)); n += 1; last += 1
                vals = {}
                for c in row.findall(NS + "c"):
                    ref = c.get("r"); j = col_index(ref) if ref else len(vals)
                    vals[j] = cell_value(c, shared, date_styles)
                width = max(ncol or 0, (max(vals) + 1) if vals else 0)
                w.writerow([vals.get(j, "") for j in range(width)]); n += 1; last = r
                row.clear()
    return n

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=os.path.join("inputs", "response", "raw", "territories"))
    ap.add_argument("--out", default=os.path.join("inputs", "response", "processed", "territories_csv"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for src, dst in FILES.items():
        sp, dp = os.path.join(a.raw, src), os.path.join(a.out, dst)
        n = convert(sp, dp)
        print("%s  sha256 %s\n -> %s  rows incl. header %d  sha256 %s" % (src, sha(sp), dst, n, sha(dp)))
