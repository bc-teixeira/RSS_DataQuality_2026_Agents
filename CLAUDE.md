# Project Coding Standards

These rules apply to every session in this project. Detailed guidance lives in `.claude/skills/`.

## Running R code (mandatory)

- ALWAYS run R scripts through the wrapper:
  ```bash
  bash .claude/scripts/run_r.sh <path_to_script.R>
  ```
- NEVER call `Rscript` or `R CMD BATCH` directly (a hook will block it).
- The wrapper writes `6_Logs/<script>_YYYYMMDD_HHMMSS.log`, moves older logs for that script to `6_Logs/archive/`, shows output live, reports duration, and prints the last 30 log lines on failure.
- Paths are relative to the project root. If a run fails, read the log in `6_Logs/` before changing code.
- Details: `.claude/scripts/run_r_README.md`.

## R style

- Tidyverse style; use the native pipe `|>` (not `%>%`) and stay consistent within a file.
- Namespace calls when helpful (`dplyr::filter()`), especially in shared functions.
- Parameters and paths defined at the top of each script; no magic numbers or hard-coded codes inside logic.
- Separate processing, analysis, and visualization code.
- Comment the "why" for non-obvious business logic; parameterize functions.
- Use `message()` for progress with step numbers and counts so logs are useful, e.g. `message("  -> Remaining: ", nrow(x), " rows")`.
- Numbered scripts where order matters: `01_*.R`, `02_*.R`, ..., `99_*.R`.

## Data handling

- Lazy first, collect last: build dbplyr pipelines remotely; `collect()` goes on its own line as the final step.
- Filter early, select columns explicitly, avoid `SELECT *`; prefer `semi_join()` before heavy joins.
- Use `show_query()` to review SQL on critical steps.
- Save intermediates as `.fst` in stage-based folders (e.g. `stage-01_ingest/`, `stage-02_clean/`); no dates in artifact paths.
- Never output patient-level data in reports; suppress counts below 10.

## Tables and figures

- Regression and survival tables: `gtsummary` (`tbl_regression`, `tbl_survfit`, `tbl_summary`), with custom labels, N and diagnostics in footnotes. No hand-built `gt()` tables where gtsummary works.
- Save tables as `.rds` and load them in Quarto.
- Figures: ggplot2 (plotly for interactive), with the BMS palette defined in `.claude/skills/r-coding/SKILL.md`.

## Markdown / Quarto

- Never use `---` as a section divider in `.md` planning docs or `.qmd` files; only for YAML front matter at the top.
- Use `{.unnumbered}` on headings in planning docs and `&nbsp;` for spacing in QMD.

## Timestamps

- Data fields: ISO 8601 UTC (`2025-10-23T16:30:00Z`); filenames: `YYYYMMDD_HHMMSS`; reports: `YYYY-MM-DD`.

## Testing

- Use `testthat` for invariants: key uniqueness, attrition counts, date ranges, row-count thresholds.

## Skills (read when relevant)

- `.claude/skills/r-coding/SKILL.md` for any `.R` work
- `.claude/skills/statistical-tables/SKILL.md` for table outputs
- `.claude/skills/formatting-standards/SKILL.md` for markdown, QMD, and timestamps
