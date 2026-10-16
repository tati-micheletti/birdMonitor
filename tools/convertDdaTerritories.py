#!/usr/bin/env python
"""Convert the two DDA territory workbooks (raw, never modified) into plain csv copies, cell for cell, for the figure script (tools/makeStCoFigures.R, section S9).

    python tools/convertDdaTerritories.py [--raw inputs/response/raw/territories] [--out inputs/response/processed/territories_csv]

Input : BirdStats_Visits2005-2024D.xlsx        -> dda_visits.csv  (Nummer, Jahr, Countdate, ROUTENCODE)
        BirdStats_Daten2005-2024D_alle.xlsx    -> dda_data.csv    (Nummer, Countdate, EURING, Reviere, Art deutsch, ROUTENCODE, Cov1)
Nothing is filtered, recoded or aggregated: every row and column of the single sheet is written as it is, dates as YYYY-MM-DD, empty cells as empty fields.
The sha256 of the inputs and of the outputs is printed, so that the copy can be shown to be a faithful conversion of a given workbook.
"""
import argparse, csv, datetime, hashlib, os
import openpyxl

FILES = {"BirdStats_Visits2005-2024D.xlsx": "dda_visits.csv", "BirdStats_Daten2005-2024D_alle.xlsx": "dda_data.csv"}

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def cell(v):
    if v is None:
        return ""
    if isinstance(v, datetime.datetime):
        return v.date().isoformat()
    return v

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=os.path.join("inputs", "response", "raw", "territories"))
    ap.add_argument("--out", default=os.path.join("inputs", "response", "processed", "territories_csv"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for src, dst in FILES.items():
        sp, dp = os.path.join(a.raw, src), os.path.join(a.out, dst)
        wb = openpyxl.load_workbook(sp, read_only=True, data_only=True)
        assert len(wb.worksheets) == 1, src + ": expected one sheet"
        n = 0
        with open(dp, "w", newline="", encoding="utf-8") as f:           # csv module default line ending (CRLF), as in the copies already used
            w = csv.writer(f)
            for row in wb.worksheets[0].iter_rows(values_only=True):
                w.writerow([cell(v) for v in row]); n += 1
        print(f"{src}  sha256 {sha(sp)}\n -> {dst}  rows incl. header {n}  sha256 {sha(dp)}")
