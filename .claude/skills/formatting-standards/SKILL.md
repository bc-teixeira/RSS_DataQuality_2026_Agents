---
name: formatting-standards
description: "Markdown/QMD formatting and timestamp standards. Use when writing planning docs or QMD files (no --- dividers, {.unnumbered} headings) and when choosing timestamp formats for data fields, filenames, and reports."
---
## � **MARKDOWN FORMATTING STANDARDS**

**CRITICAL:** Planning documents and QMD files must NOT use `---` as section dividers, as these are interpreted as YAML headers and will break parsing.

### **Rules by File Type**

**Planning Documents (5_Documents/*.md):**
- ❌ **NEVER use `---` as section dividers** (conflicts with YAML front matter)
- ✅ Use `{.unnumbered}` after ALL section headings to prevent numbering conflicts
- ✅ Use blank lines or `## Section Name {.unnumbered}` for section breaks
- ✅ YAML front matter allowed ONLY at top of file (lines 1-N before first content)

**QMD Reports (3_Reports/*.qmd, *.QMD):**
- ❌ **NEVER use `---` as section dividers** (conflicts with YAML headers)
- ✅ Use `&nbsp;` for spacing/visual breaks in rendered output
- ✅ Use heading levels (`#`, `##`, `###`) for structure
- ✅ YAML front matter allowed ONLY at top of file (lines 1-N before first content)

**Prompt Files (.claude/commands/*.md, .claude/skills/*.md):**
- ✅ Can use `---` freely for section breaks (not parsed as documents)
- ✅ YAML front matter at top for metadata

**Examples:**

```markdown
# ✅ CORRECT - Planning Document (5_Documents/01_Summary.md)
---
document_version: 1.0
created: 2026-01-14
---

## Study Design {.unnumbered}
Content here...

## Data Sources {.unnumbered}
Content here...

<!-- No --- dividers in body -->
```

```markdown
# ✅ CORRECT - QMD Report (3_Reports/Results.qmd)
---
title: "Study Results"
format: bms-html
---

## Executive Summary
Key findings...

&nbsp;

## Methods
Study design...

<!-- Use &nbsp; for visual spacing, not --- -->
```

```markdown
# ❌ WRONG - Planning Document
## Study Design {.unnumbered}
Content...

---  <!-- BREAKS PARSING - interpreted as new YAML block -->

## Data Sources {.unnumbered}
Content...
```

## �📅 **TIMESTAMP STANDARDS**

To ensure consistency across logs, task tracking, and file naming:

### **ISO8601 for Data Fields**
- **Format:** `YYYY-MM-DDTHH:MM:SSZ` (e.g., `2025-10-23T16:30:00Z`)
- **Usage:** Task `start_time` and `end_time` in `06_Tasks.md`, database timestamps, API responses
- **Rationale:** Standardized, sortable, unambiguous with timezone (UTC preferred)
- **R code:** `format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")`
- **Bash code:** `date -u +"%Y-%m-%dT%H:%M:%SZ"`

### **File-Safe Format for Filenames**
- **Format:** `YYYYMMDD_HHMMSS` (e.g., `20251023_163000`)
- **Usage:** Log files (`6_Logs/*_YYYYMMDD_HHMMSS.log`), archive folders, artifact timestamps
- **Rationale:** No special characters, sorts correctly, filesystem-compatible
- **R code:** `format(Sys.time(), "%Y%m%d_%H%M%S")`
- **Bash code:** `date +"%Y%m%d_%H%M%S"`

### **Human-Readable Format for Reports**
- **Format:** `YYYY-MM-DD` (e.g., `2025-10-23`)
- **Usage:** Document dates in markdown files, report headers, display-only contexts
- **Rationale:** Readable, sortable, internationally recognized
- **R code:** `format(Sys.Date(), "%Y-%m-%d")`
- **Bash code:** `date +"%Y-%m-%d"`

### **Examples by Context**
```r
# Task tracking (06_Tasks.md)
start_time: "2025-10-23T09:00:00Z"  # ISO8601

# Log files (6_Logs/)
"01_Cohort_20251023_090000.log"     # File-safe

# Reports (3_Reports/Results.qmd)
"Analysis Date: 2025-10-23"         # Human-readable

# Artifacts (/mnt/artifacts/) - NO DATES IN PATHS
"stage-03_cohort/baseline_vars.fst" # Stage-based only
```

