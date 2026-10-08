#!/usr/bin/env python
"""
dq_profile.py - mechanical data quality profiling in the spirit of Redman, Hoerl and Tate.

Computes, for a tabular file:
  * initial data analysis: shape, types, empty/constant/high-cardinality columns, placeholder values,
    numeric and categorical summaries
  * completeness, validity (rules), uniqueness, cross-field consistency per critical data element (CDE)
  * the record-level perfect-record score (Redman's Friday Afternoon Measurement arithmetic) with a Wilson CI
  * an error Pareto
  * defect rate by period with p-chart limits and by group with funnel limits (variation across units and time)
  * date spikes (batch / retrospective entry)
  * a FAM worksheet of the most recent N records for a human pass

Usage:
  python dq_profile.py data.csv --critical a,b,c [--rules rules.json] [--key id]
         [--date-col d] [--period M|Q|Y] [--group-col g] [--fam-sample 100] [--out dq_output]
         [--nrows N] [--no-plots]

Outputs in --out: dq_profile.json, dq_summary.md, fam_worksheet.csv, and PNG charts when matplotlib exists.
Only pandas and numpy are required.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from datetime import date

import numpy as np
import pandas as pd

DEFAULT_PLACEHOLDERS = ["", "NA", "N/A", "NULL", "null", "None", "none", "-", "?", "UNKNOWN", "Unknown",
                        "unknown", "9999", "-999", "999", "-1", "NaN", "nan", "."]
PLACEHOLDER_DATES = {"1900-01-01", "1970-01-01", "9999-12-31", "1899-12-30"}
BENCHMARK_BAR = 97.0


# ----------------------------------------------------------------------------- helpers
def wilson_ci(successes: int, n: int, z: float = 1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p = successes / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half) * 100, min(1.0, centre + half) * 100)


def load_table(path: str, nrows: int | None):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".csv", ".txt"):
        try:
            return pd.read_csv(path, nrows=nrows, low_memory=False)
        except UnicodeDecodeError:
            return pd.read_csv(path, nrows=nrows, low_memory=False, encoding="latin-1")
    if ext == ".tsv":
        return pd.read_csv(path, sep="\t", nrows=nrows, low_memory=False)
    if ext in (".xlsx", ".xls"):
        return pd.read_excel(path, nrows=nrows)
    if ext == ".parquet":
        df = pd.read_parquet(path)
        return df.head(nrows) if nrows else df
    if ext in (".json", ".jsonl"):
        df = pd.read_json(path, lines=(ext == ".jsonl"))
        return df.head(nrows) if nrows else df
    raise SystemExit(f"Unsupported file type: {ext}")


def load_rules(path: str | None):
    if not path:
        return {"placeholders": DEFAULT_PLACEHOLDERS, "columns": {}, "cross_field": []}
    with open(path, "r", encoding="utf-8") as fh:
        rules = json.load(fh)
    rules.setdefault("placeholders", DEFAULT_PLACEHOLDERS)
    rules.setdefault("columns", {})
    rules.setdefault("cross_field", [])
    return rules


def is_placeholder_series(s: pd.Series, placeholders: list[str]) -> pd.Series:
    """True where the raw value is a sentinel masquerading as data (not already null)."""
    txt = s.astype("string").str.strip()
    mask = txt.isin(placeholders) & s.notna()
    # numeric sentinels typed as numbers
    if pd.api.types.is_numeric_dtype(s):
        num_sentinels = {float(p) for p in placeholders if re.fullmatch(r"-?\d+(\.\d+)?", p)}
        mask = mask | s.isin(list(num_sentinels))
    # sentinel dates
    mask = mask | txt.str[:10].isin(PLACEHOLDER_DATES)
    return mask.fillna(False).astype(bool)


def coerce(df: pd.DataFrame, col_rules: dict, date_col: str | None):
    """Parse date and numeric columns named in rules (and the date column); return parsed copy + parse failures."""
    parsed = df.copy()
    parse_fail = {}
    for col, r in col_rules.items():
        if col not in parsed.columns:
            continue
        t = r.get("type")
        if t == "date":
            conv = pd.to_datetime(parsed[col], errors="coerce")
            parse_fail[col] = int((conv.isna() & parsed[col].notna()).sum())
            parsed[col] = conv
        elif t == "number":
            conv = pd.to_numeric(parsed[col], errors="coerce")
            parse_fail[col] = int((conv.isna() & parsed[col].notna()).sum())
            parsed[col] = conv
    if date_col and date_col in parsed.columns and not pd.api.types.is_datetime64_any_dtype(parsed[date_col]):
        parsed[date_col] = pd.to_datetime(parsed[date_col], errors="coerce")
    # opportunistic: parse columns that look like dates by name
    for col in parsed.columns:
        if col in col_rules or col == date_col:
            continue
        if parsed[col].dtype == object and re.search(r"(date|_dt$|time)", col, re.I):
            conv = pd.to_datetime(parsed[col], errors="coerce")
            if conv.notna().sum() >= 0.8 * parsed[col].notna().sum() and parsed[col].notna().sum() > 0:
                parsed[col] = conv
    return parsed, parse_fail


# ----------------------------------------------------------------------------- IDA
def initial_data_analysis(raw: pd.DataFrame, parsed: pd.DataFrame, placeholders: list[str]):
    n = len(raw)
    out = {"n_rows": int(n), "n_cols": int(raw.shape[1]),
           "memory_mb": round(float(raw.memory_usage(deep=True).sum()) / 1e6, 2),
           "columns": {}, "empty_columns": [], "constant_columns": [], "high_cardinality_columns": [],
           "full_row_duplicates": int(raw.duplicated().sum())}
    for col in raw.columns:
        s = raw[col]
        ph = is_placeholder_series(s, placeholders)
        nn = int(s.notna().sum())
        info = {"dtype": str(parsed[col].dtype), "non_null": nn, "null_pct": round(100 * (1 - nn / n), 2) if n else None,
                "placeholder_count": int(ph.sum()), "distinct": int(s.nunique(dropna=True))}
        if nn == 0:
            out["empty_columns"].append(col)
        elif info["distinct"] == 1:
            out["constant_columns"].append(col)
        if s.dtype == object and nn and info["distinct"] / nn > 0.95 and info["distinct"] > 50:
            out["high_cardinality_columns"].append(col)
        ps = parsed[col]
        if pd.api.types.is_numeric_dtype(ps) and nn:
            q = ps.quantile([0.01, 0.5, 0.99])
            info["numeric"] = {"min": _f(ps.min()), "p01": _f(q.iloc[0]), "median": _f(q.iloc[1]),
                               "p99": _f(q.iloc[2]), "max": _f(ps.max()), "mean": _f(ps.mean()), "std": _f(ps.std())}
            info["bimodality_hint"] = _bimodality_hint(ps.dropna())
        elif pd.api.types.is_datetime64_any_dtype(ps) and ps.notna().any():
            info["date_range"] = [str(ps.min().date()), str(ps.max().date())]
            info["future_dates"] = int((ps > pd.Timestamp.today()).sum())
        else:
            vc = s.astype("string").value_counts(dropna=True).head(8)
            info["top_values"] = {str(k): int(v) for k, v in vc.items()}
        out["columns"][col] = info
    return out


def _f(x):
    try:
        if x is None or (isinstance(x, float) and math.isnan(x)):
            return None
        return float(round(float(x), 4))
    except Exception:
        return None


def _bimodality_hint(x: pd.Series):
    """Crude bimodality coefficient; > 0.555 suggests more than one mode (unit mix, mixed definitions)."""
    nun = x.nunique()
    if len(x) < 30 or x.std() == 0 or nun < 20 or nun / len(x) > 0.9:
        return None  # too few values, categorical-like, or ID-like
    z = (x - x.mean()) / x.std()
    n = len(x)
    skew = float((z ** 3).mean())
    kurt = float((z ** 4).mean()) - 3
    bc = (skew ** 2 + 1) / (kurt + 3 * (n - 1) ** 2 / ((n - 2) * (n - 3)))
    return {"bimodality_coefficient": round(bc, 3), "possible_multimodal": bool(bc > 0.555)}


# ----------------------------------------------------------------------------- rules / errors
def apply_rules(raw: pd.DataFrame, parsed: pd.DataFrame, critical: list[str], rules: dict, parse_fail: dict):
    """Return error matrix (bool DataFrame rows x error_type), per-column results, weak flags."""
    n = len(raw)
    placeholders = rules["placeholders"]
    errors = {}
    weak = {}
    col_results = {}
    today = pd.Timestamp.today().normalize()

    for col in critical:
        if col not in raw.columns:
            col_results[col] = {"missing_column": True}
            errors[f"{col}: column missing"] = pd.Series(True, index=raw.index)
            continue
        r = rules["columns"].get(col, {})
        s_raw = raw[col]
        s = parsed[col]
        ph = is_placeholder_series(s_raw, placeholders)
        missing = s_raw.isna() | ph
        res = {"null_count": int(s_raw.isna().sum()), "placeholder_count": int(ph.sum()),
               "completeness_pct": round(100 * (1 - missing.sum() / n), 2) if n else None}
        if r.get("not_null", True):
            errors[f"{col}: missing/placeholder"] = missing
        if col in parse_fail and parse_fail[col]:
            bad = s.isna() & s_raw.notna() & ~ph
            errors[f"{col}: unparseable {r.get('type')}"] = bad
            res["unparseable"] = int(bad.sum())
        if "allowed" in r:
            allowed = [str(a) for a in r["allowed"]]
            bad = s_raw.notna() & ~ph & ~s_raw.astype("string").isin(allowed).fillna(False)
            errors[f"{col}: not in allowed values"] = bad
            res["invalid_values"] = int(bad.sum())
            res["invalid_examples"] = [str(v) for v in s_raw[bad].astype("string").value_counts().head(5).index]
        if "flag_values" in r:
            w = s_raw.astype("string").isin([str(a) for a in r["flag_values"]]).fillna(False)
            weak[f"{col}: weak/proxy value"] = w
            res["weak_values"] = int(w.sum())
        if "regex" in r:
            pat = re.compile(r["regex"])
            txt = s_raw.astype("string")
            bad = s_raw.notna() & ~ph & ~txt.apply(lambda v: bool(pat.fullmatch(v)) if pd.notna(v) else True)
            errors[f"{col}: regex mismatch"] = bad.fillna(False)
            res["regex_mismatch"] = int(bad.sum())
        lo, hi = r.get("min"), r.get("max")
        if lo is not None or hi is not None:
            if pd.api.types.is_datetime64_any_dtype(s):
                lo_v = today if lo == "today" else (pd.Timestamp(lo) if lo is not None else None)
                hi_v = today if hi == "today" else (pd.Timestamp(hi) if hi is not None else None)
            else:
                lo_v = float(lo) if lo is not None else None
                hi_v = float(hi) if hi is not None else None
            bad = pd.Series(False, index=raw.index)
            if lo_v is not None:
                bad |= (s < lo_v).fillna(False)
            if hi_v is not None:
                bad |= (s > hi_v).fillna(False)
            errors[f"{col}: out of range"] = bad
            res["out_of_range"] = int(bad.sum())
            res["range"] = [str(lo), str(hi)]
        if r.get("unique"):
            dup = s_raw.notna() & s_raw.duplicated(keep="first")
            errors[f"{col}: duplicate value"] = dup
            res["duplicates"] = int(dup.sum())
        col_results[col] = res

    for cf in rules.get("cross_field", []):
        name = cf.get("name", cf.get("expr"))
        try:
            ok = parsed.eval(cf["expr"], engine="python")
            ok = pd.Series(ok, index=parsed.index)
            # Rows with a missing value in any referenced column pass this rule: missingness is already
            # counted by the column rules, and comparisons with NaT/NaN silently return False.
            referenced = [c for c in parsed.columns if re.search(rf"(?<![\w.]){re.escape(str(c))}(?![\w])", cf["expr"])]
            has_na = parsed[referenced].isna().any(axis=1) if referenced else pd.Series(False, index=parsed.index)
            fail = (~ok.astype("boolean").fillna(True)).astype(bool) & ~has_na
            errors[f"rule: {name}"] = fail
        except Exception as exc:  # keep going; report the broken rule
            errors[f"rule: {name} (FAILED TO EVALUATE: {exc})"] = pd.Series(False, index=parsed.index)

    err_df = pd.DataFrame(errors) if errors else pd.DataFrame(index=raw.index)
    weak_df = pd.DataFrame(weak) if weak else pd.DataFrame(index=raw.index)
    return err_df, weak_df, col_results


def perfect_record_score(err_df: pd.DataFrame):
    n = len(err_df)
    if n == 0 or err_df.shape[1] == 0:
        return {"n_records": n, "perfect_records": n, "score_pct": None, "ci95_pct": None}
    any_err = err_df.any(axis=1)
    perfect = int((~any_err).sum())
    lo, hi = wilson_ci(perfect, n)
    score = 100 * perfect / n
    return {"n_records": int(n), "perfect_records": perfect, "defective_records": int(n - perfect),
            "score_pct": round(score, 2), "ci95_pct": [round(lo, 2), round(hi, 2)],
            "meets_97_bar": bool(lo >= BENCHMARK_BAR),
            "errors_per_defective_record": round(float(err_df.sum(axis=1)[any_err].mean()), 2) if perfect < n else 0.0,
            "redman_benchmark": "Across 75 organisations (Nagle, Redman & Sammon 2017): half of scores below 57%, "
                                "a quarter below 30%, 3% at or above 97%."}


def pareto(err_df: pd.DataFrame):
    if err_df.shape[1] == 0:
        return []
    counts = err_df.sum().sort_values(ascending=False)
    total = counts.sum()
    cum = 0
    rows = []
    for name, c in counts.items():
        if c == 0:
            continue
        cum += c
        rows.append({"error_type": name, "count": int(c), "share_pct": round(100 * c / total, 2) if total else 0,
                     "cumulative_pct": round(100 * cum / total, 2) if total else 0})
    return rows


# ----------------------------------------------------------------------------- variation
def p_chart(defective: pd.Series, groups: pd.Series, label: str):
    """Defect proportion per group with 3-sigma limits (variable n). Flags out-of-control groups."""
    d = pd.DataFrame({"def": defective.astype(int), "g": groups})
    d = d[d["g"].notna()]
    if d.empty:
        return None
    agg = d.groupby("g")["def"].agg(["sum", "count"])
    pbar = agg["sum"].sum() / agg["count"].sum()
    agg["p"] = agg["sum"] / agg["count"]
    sigma = np.sqrt(pbar * (1 - pbar) / agg["count"])
    agg["ucl"] = np.minimum(1, pbar + 3 * sigma)
    agg["lcl"] = np.maximum(0, pbar - 3 * sigma)
    agg["out_of_control"] = (agg["p"] > agg["ucl"]) | (agg["p"] < agg["lcl"])
    rows = [{label: str(idx), "n": int(r["count"]), "defective": int(r["sum"]), "defect_rate_pct": round(100 * r["p"], 2),
             "ucl_pct": round(100 * r["ucl"], 2), "lcl_pct": round(100 * r["lcl"], 2),
             "out_of_control": bool(r["out_of_control"])} for idx, r in agg.iterrows()]
    return {"centre_line_pct": round(100 * pbar, 2), "n_groups": int(len(agg)),
            "out_of_control_groups": [r[label] for r in rows if r["out_of_control"]],
            "range_pct": [round(100 * agg["p"].min(), 2), round(100 * agg["p"].max(), 2)], "rows": rows}


def date_spikes(dates: pd.Series, factor: float = 10.0, min_count: int = 20):
    d = dates.dropna().dt.normalize()
    if d.empty:
        return None
    vc = d.value_counts()
    med = float(vc.median())
    spikes = vc[(vc > factor * max(med, 1)) & (vc >= min_count)]
    return {"median_records_per_day": med, "n_days": int(len(vc)),
            "spikes": [{"date": str(k.date()), "count": int(v), "x_median": round(v / max(med, 1), 1)}
                       for k, v in spikes.head(15).items()],
            "future_dates": int((dates > pd.Timestamp.today()).sum()), "missing_dates": int(dates.isna().sum())}


def missingness_trend(parsed: pd.DataFrame, critical: list[str], period_key: pd.Series):
    present = [c for c in critical if c in parsed.columns]
    if not present:
        return None
    miss = parsed[present].isna().astype(int)
    miss["_p"] = period_key
    g = miss[miss["_p"].notna()].groupby("_p").mean() * 100
    return {str(idx): {c: round(float(v), 2) for c, v in row.items()} for idx, row in g.iterrows()}


# ----------------------------------------------------------------------------- FAM worksheet
def fam_worksheet(raw: pd.DataFrame, parsed: pd.DataFrame, err_df: pd.DataFrame, critical: list[str],
                  date_col: str | None, n: int, out_dir: str):
    present = [c for c in critical if c in raw.columns]
    if date_col and date_col in parsed.columns:
        idx = parsed[date_col].sort_values(na_position="first").index[-n:]
    else:
        idx = raw.index[-n:]
    ws = raw.loc[idx, present].copy()
    flags = err_df.loc[idx]
    ws.insert(0, "_record_index", idx)
    ws["_auto_flags"] = flags.apply(lambda r: "; ".join(flags.columns[r.values.astype(bool)]), axis=1)
    ws["perfect_record"] = ""  # for the human pass
    ws["reviewer_notes"] = ""
    path = os.path.join(out_dir, "fam_worksheet.csv")
    ws.to_csv(path, index=False)
    return path, int(len(ws))


# ----------------------------------------------------------------------------- plots
def make_plots(result: dict, out_dir: str):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:
        return []
    made = []
    pr = result.get("pareto") or []
    if pr:
        top = pr[:12]
        fig, ax = plt.subplots(figsize=(9, 4.5))
        ax.bar(range(len(top)), [r["count"] for r in top], color="#4a6fa5")
        ax.set_xticks(range(len(top)))
        ax.set_xticklabels([r["error_type"][:38] for r in top], rotation=40, ha="right", fontsize=8)
        ax2 = ax.twinx()
        ax2.plot(range(len(top)), [r["cumulative_pct"] for r in top], color="#c0504d", marker="o")
        ax2.set_ylim(0, 105)
        ax2.set_ylabel("cumulative %")
        ax.set_ylabel("errors")
        ax.set_title("Error Pareto (critical data elements)")
        fig.tight_layout()
        p = os.path.join(out_dir, "pareto.png")
        fig.savefig(p, dpi=130)
        plt.close(fig)
        made.append(p)
    for key, fname, title in (("by_period", "pchart.png", "Defect rate by period (p-chart, 3-sigma limits)"),
                              ("by_group", "funnel.png", "Defect rate by group (3-sigma limits)")):
        pc = result.get("variation", {}).get(key)
        if pc and pc.get("rows"):
            rows = pc["rows"]
            lab = [list(r.keys())[0] for r in rows][0]
            x = range(len(rows))
            fig, ax = plt.subplots(figsize=(9, 4.5))
            ax.plot(x, [r["defect_rate_pct"] for r in rows], marker="o", color="#4a6fa5", label="defect rate %")
            ax.plot(x, [r["ucl_pct"] for r in rows], linestyle="--", color="#c0504d", label="UCL")
            ax.plot(x, [r["lcl_pct"] for r in rows], linestyle="--", color="#c0504d", label="LCL")
            ax.axhline(pc["centre_line_pct"], color="grey", linewidth=1, label="centre")
            ooc = [i for i, r in enumerate(rows) if r["out_of_control"]]
            if ooc:
                ax.scatter(ooc, [rows[i]["defect_rate_pct"] for i in ooc], color="#c0504d", zorder=5, s=60)
            ax.set_xticks(list(x))
            ax.set_xticklabels([r[lab] for r in rows], rotation=60, ha="right", fontsize=7)
            ax.set_ylabel("% defective records")
            ax.set_title(title)
            ax.legend(fontsize=8)
            fig.tight_layout()
            p = os.path.join(out_dir, fname)
            fig.savefig(p, dpi=130)
            plt.close(fig)
            made.append(p)
    comp = result.get("critical_columns", {})
    if comp:
        cols = [c for c, v in comp.items() if "completeness_pct" in v]
        if cols:
            fig, ax = plt.subplots(figsize=(8, 0.4 * len(cols) + 1.5))
            ax.barh(cols, [comp[c]["completeness_pct"] for c in cols], color="#4a6fa5")
            ax.set_xlim(0, 100)
            ax.axvline(BENCHMARK_BAR, color="#c0504d", linestyle="--")
            ax.set_xlabel("% complete (non-null, non-placeholder)")
            ax.set_title("Completeness of critical data elements")
            fig.tight_layout()
            p = os.path.join(out_dir, "completeness.png")
            fig.savefig(p, dpi=130)
            plt.close(fig)
            made.append(p)
    return made


# ----------------------------------------------------------------------------- summary
def write_summary(result: dict, out_dir: str):
    s = result["perfect_record_score"]
    L = []
    L.append(f"# Data quality profile: {os.path.basename(result['source'])}\n")
    L.append(f"Rows: {result['ida']['n_rows']:,}  Columns: {result['ida']['n_cols']}  "
             f"Critical data elements: {len(result['critical'])}\n")
    if s.get("score_pct") is not None:
        lo, hi = s["ci95_pct"]
        L.append(f"## Perfect-record score: **{s['score_pct']}%** (95% CI {lo} to {hi})\n")
        L.append(f"{s['perfect_records']:,} of {s['n_records']:,} records have no error in any critical element. "
                 f"Bar: {BENCHMARK_BAR}% (Redman's loosest acceptable standard). "
                 f"{'Meets' if s['meets_97_bar'] else 'Does not meet'} the bar. {s['redman_benchmark']}\n")
        L.append("This automated score counts only errors a rule anticipated; it is a lower bound on the true error rate. "
                 "Do the human pass on the FAM worksheet to catch the rest.\n")
        if not result.get("rules_file"):
            L.append("**No rules file was supplied**, so the score reflects missing values and placeholders only. "
                     "Write a rules.json from the data customer's error definitions (ranges, allowed values, "
                     "cross-field checks) and re-run; see references/rules-format.md.\n")
    L.append("## Critical data elements\n")
    L.append("| Column | Completeness % | Nulls | Placeholders | Invalid | Out of range | Duplicates | Weak/proxy |")
    L.append("|---|---|---|---|---|---|---|---|")
    for c, v in result["critical_columns"].items():
        if v.get("missing_column"):
            L.append(f"| {c} | COLUMN MISSING | | | | | | |")
            continue
        L.append(f"| {c} | {v.get('completeness_pct')} | {v.get('null_count')} | {v.get('placeholder_count')} | "
                 f"{v.get('invalid_values', v.get('regex_mismatch', ''))} | {v.get('out_of_range', '')} | "
                 f"{v.get('duplicates', '')} | {v.get('weak_values', '')} |")
    L.append("")
    if result["pareto"]:
        L.append("## Error Pareto\n")
        L.append("| Error type | Count | Share % | Cumulative % |")
        L.append("|---|---|---|---|")
        for r in result["pareto"][:15]:
            L.append(f"| {r['error_type']} | {r['count']} | {r['share_pct']} | {r['cumulative_pct']} |")
        L.append("")
    ida = result["ida"]
    L.append("## Initial data analysis flags\n")
    L.append(f"- Full-row duplicates: {ida['full_row_duplicates']}")
    if result.get("key_duplicates") is not None:
        L.append(f"- Duplicate keys on `{result['key']}`: {result['key_duplicates']}")
    if ida["empty_columns"]:
        L.append(f"- Empty columns: {', '.join(ida['empty_columns'])}")
    if ida["constant_columns"]:
        L.append(f"- Constant columns: {', '.join(ida['constant_columns'])}")
    ph = {c: v["placeholder_count"] for c, v in ida["columns"].items() if v["placeholder_count"]}
    if ph:
        L.append("- Placeholder values found: " + ", ".join(f"{c} ({n})" for c, n in ph.items()))
    bim = [c for c, v in ida["columns"].items() if v.get("bimodality_hint", {}) and v["bimodality_hint"].get("possible_multimodal")]
    if bim:
        L.append(f"- Possibly multimodal numeric columns (check for unit or definition mixes): {', '.join(bim)}")
    fut = {c: v["future_dates"] for c, v in ida["columns"].items() if v.get("future_dates")}
    if fut:
        L.append("- Future dates: " + ", ".join(f"{c} ({n})" for c, n in fut.items()))
    L.append("")
    var = result.get("variation", {})
    if var.get("by_period"):
        pc = var["by_period"]
        L.append("## Stability over time (p-chart)\n")
        L.append(f"- Centre line {pc['centre_line_pct']}% defective across {pc['n_groups']} periods; "
                 f"range {pc['range_pct'][0]}% to {pc['range_pct'][1]}%.")
        L.append(f"- Out-of-control periods: {', '.join(pc['out_of_control_groups']) or 'none'}\n")
    if var.get("by_group"):
        pc = var["by_group"]
        L.append("## Variation across units\n")
        L.append(f"- Centre line {pc['centre_line_pct']}% defective across {pc['n_groups']} groups; "
                 f"range {pc['range_pct'][0]}% to {pc['range_pct'][1]}%.")
        L.append(f"- Groups outside 3-sigma limits: {', '.join(pc['out_of_control_groups']) or 'none'}\n")
    if var.get("date_spikes") and var["date_spikes"].get("spikes"):
        L.append("## Date spikes (possible batch or retrospective entry)\n")
        for sp in var["date_spikes"]["spikes"]:
            L.append(f"- {sp['date']}: {sp['count']} records ({sp['x_median']}x the daily median)")
        L.append("")
    L.append("## What this script cannot tell you\n")
    L.append("- Accuracy against reality (needs a reference source or the human FAM pass).")
    L.append("- Whether this is the right data for the decision (population match, pedigree, definitions).")
    L.append("- Records that should exist but do not (coverage, false negatives).")
    L.append(f"\nFAM worksheet: {result.get('fam_worksheet')}  Charts: {', '.join(os.path.basename(p) for p in result.get('plots', [])) or 'none'}\n")
    path = os.path.join(out_dir, "dq_summary.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))
    return path


# ----------------------------------------------------------------------------- main
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data")
    ap.add_argument("--critical", required=True, help="comma-separated critical data elements")
    ap.add_argument("--rules", help="rules.json (see references/rules-format.md)")
    ap.add_argument("--key", help="record key column(s) for duplicate check; comma-separate a composite key, "
                                  "e.g. patient_id,test_date,analyte")
    ap.add_argument("--date-col", help="event/record date for time-ordered analysis")
    ap.add_argument("--period", default="Q", help="M, Q or Y (default Q)")
    ap.add_argument("--group-col", help="site/source/practice column for variation across units")
    ap.add_argument("--fam-sample", type=int, default=100)
    ap.add_argument("--out", default="dq_output")
    ap.add_argument("--nrows", type=int)
    ap.add_argument("--no-plots", action="store_true")
    a = ap.parse_args(argv)

    os.makedirs(a.out, exist_ok=True)
    raw = load_table(a.data, a.nrows)
    rules = load_rules(a.rules)
    critical = [c.strip() for c in a.critical.split(",") if c.strip()]
    missing_cols = [c for c in critical if c not in raw.columns]
    if missing_cols:
        print(f"WARNING: critical columns not in data: {missing_cols}", file=sys.stderr)

    parsed, parse_fail = coerce(raw, rules["columns"], a.date_col)
    ida = initial_data_analysis(raw, parsed, rules["placeholders"])
    err_df, weak_df, col_results = apply_rules(raw, parsed, critical, rules, parse_fail)
    score = perfect_record_score(err_df)
    par = pareto(err_df)
    defective = err_df.any(axis=1) if err_df.shape[1] else pd.Series(False, index=raw.index)

    variation = {}
    if a.date_col and a.date_col in parsed.columns:
        dts = parsed[a.date_col]
        period_key = dts.dt.to_period(a.period).astype(str).where(dts.notna())
        variation["by_period"] = p_chart(defective, period_key, "period")
        variation["date_spikes"] = date_spikes(dts)
        variation["missingness_by_period_pct"] = missingness_trend(parsed, critical, period_key)
        variation["volume_by_period"] = {str(k): int(v) for k, v in period_key.value_counts().sort_index().items()}
    if a.group_col and a.group_col in raw.columns:
        variation["by_group"] = p_chart(defective, raw[a.group_col].astype("string"), "group")
        if a.date_col and a.date_col in parsed.columns:
            dts = parsed[a.date_col]
            period_key = dts.dt.to_period(a.period).astype(str).where(dts.notna())
            tab = pd.crosstab(raw[a.group_col].astype("string"), period_key, values=defective.astype(int), aggfunc="mean")
            variation["defect_rate_group_by_period_pct"] = {str(g): {str(p): (None if pd.isna(v) else round(100 * float(v), 2))
                                                                     for p, v in row.items()} for g, row in tab.iterrows()}

    key_dups = None
    key_cols = [k.strip() for k in (a.key or "").split(",") if k.strip() and k.strip() in raw.columns]
    if key_cols:
        key_dup_mask = raw.duplicated(subset=key_cols, keep="first")
        key_dups = int(key_dup_mask.sum())
        # a duplicate key is a record-level defect: fold it into the score and the Pareto
        err_df[f"key duplicate ({'+'.join(key_cols)})"] = key_dup_mask
        score = perfect_record_score(err_df)
        par = pareto(err_df)
        defective = err_df.any(axis=1)

    fam_path, fam_n = fam_worksheet(raw, parsed, err_df, critical, a.date_col, a.fam_sample, a.out)

    result = {"source": os.path.abspath(a.data), "critical": critical, "rules_file": a.rules,
              "key": a.key, "key_duplicates": key_dups, "date_col": a.date_col, "group_col": a.group_col,
              "ida": ida, "critical_columns": col_results,
              "weak_values": {c: int(v.sum()) for c, v in weak_df.items()} if weak_df.shape[1] else {},
              "perfect_record_score": score, "pareto": par, "variation": variation,
              "fam_worksheet": fam_path, "fam_rows": fam_n,
              "benchmarks": {"acceptable_bar_pct": BENCHMARK_BAR, "rule_of_ten": "defective inputs cost ~10x to process"}}
    result["plots"] = [] if a.no_plots else make_plots(result, a.out)
    with open(os.path.join(a.out, "dq_profile.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, default=str)
    summ = write_summary(result, a.out)
    with open(summ, "r", encoding="utf-8") as fh:
        print(fh.read())
    print(f"\nWrote: {os.path.join(a.out, 'dq_profile.json')}, {summ}, {fam_path}" +
          (f", {', '.join(result['plots'])}" if result["plots"] else ""))


if __name__ == "__main__":
    main()
