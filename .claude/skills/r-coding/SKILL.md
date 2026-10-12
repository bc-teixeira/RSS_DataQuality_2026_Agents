---
name: r-coding
description: "R coding standards. Use when writing or editing any .R script: style, packages, database access, artifacts, plotting, testing, logging."
---

> Applies to files matching: `**/*.R`

# R Coding Standards

## Suggested project layout
```
project/
├── 0_Setup/Setup.R        # libraries + connection helpers; source from analysis scripts
├── 1_Codelists/           # all codelists defined/processed here only
├── 2_Code/                # analysis code; numeric sequence: 01_*.R, 02_*.R, ... 99_*.R
├── 3_Reports/             # Quarto reports and Outputs/ (P001/, S001/, E001/ by ID)
├── 4_Tests/               # *_Tests.R
├── 5_Documents/           # planning docs and source material
├── 6_Logs/                # execution logs (managed by run_r.sh) and archive/
└── .claude/
```

## Running scripts
Always use `bash .claude/scripts/run_r.sh <script.R>`. Never run `Rscript` directly. See `.claude/scripts/run_r_README.md`.

## Style
- Tidyverse style; prefer `|>` over `%>%` (consistency within a file matters most).
- Separate processing, analysis, and visualization code.
- Define parameters at the top of the script.
- Comment complex logic; parameterize functions.
- No hard-coded medical codes in analysis scripts; load them from `1_Codelists/`.
- Add `message()` calls at each step with counts, so logs show progress:
  ```r
  message("Step 1: Loading enrollment data...")
  message("  -> Loaded ", nrow(data), " patients")
  ```

## Database operations (dbplyr)
- **Lazy first, collect last**: build pipelines remotely; `collect()` on its own line as the last step.
- `compute()` to materialize heavy intermediates as temporary tables when helpful.
- Intermediate writes to the database go to the designated scratch schema only (never production schemas).
- Filter as early as possible; use `semi_join()` to reduce remote rows before heavy joins.
- Use `show_query()` on critical steps during review.
- Source the shared connection helper rather than re-creating connections:
  ```r
  source("0_Setup/Setup.R")
  visits <- dbplyr::tbl(con, dbplyr::in_schema("cdm", "visits"))
  ```
- Lazy -> compute (optional) -> collect:
  ```r
  patient_query <- visits |>
    dplyr::filter(condition_code %in% condition_codes) |>
    dplyr::select(person_id) |>
    dplyr::distinct()

  treatment_query <- treatment_tbl |>
    dplyr::semi_join(patient_query, by = "person_id")

  df_treat <- treatment_query |>
    dplyr::collect()
  ```

## Packages
- Core: `DBI`, `RPostgres`, `dbplyr`, `dplyr`, `readr`, `tidyr`, `stringr`, `purrr`, `glue`
- Tables/reporting: `gt`, `gtsummary`, `quarto`
- Testing: `testthat`
- Artifacts: `fst`

## Intermediate artifacts (fst)
Save data frames as `.fst` under stage folders. No dates in artifact paths.
```r
fst::write_fst(df_clean, "/mnt/artifacts/stage-02_clean/clean.fst")
df_clean <- fst::read_fst("/mnt/artifacts/stage-02_clean/clean.fst")
```
Suggested stages: `stage-01_ingest`, `stage-02_clean`, `stage-03_cohort`, `stage-04_attrition`, `stage-05_outputs`.

## Cohorts and attrition
- Parameterized cohort builders with clear inclusion/exclusion booleans.
- Compute all attrition criteria in ONE `mutate()`; build the final `attrition` flag with boolean operators (`&`, `!`) and individual flags with `%in%`, so each criterion can be inspected (e.g. `sum(flag)`).
- Name each step; order filters logically; record attrition as a reproducible table.

## Performance
- Push computation to the database; filter early; select columns explicitly; no `SELECT *` in committed SQL.
- Cache heavy steps with `compute()` or fst; be mindful of memory when collecting.

## Plotting and reporting
- plotly for interactive review; ggplot2 for complex static layering (`plotly::ggplotly()` to convert).
- All visualizations use the BMS palette below.
- Quarto defaults: self-contained HTML, gtsummary for tables.

```yaml
format:
  html:
    embed-resources: true
    code-fold: true
    code-summary: "Show the code"
number-sections: true
execute:
  warning: false
  message: false
  echo: false
```

### BMS color palette (mandatory for visualizations)
```r
bms_colors <- list(
  purple = "#BE2BBB", dark_gray = "#595959", gray = "#A6A69F", light_gray = "#EEE7E7",
  amber = "#FFECCD", peach = "#FCDCCA", sienna = "#DAC5C5", mint = "#C5FFE6",
  aqua = "#C0F2FB", olive = "#EAD5C9", almond = "#DFCBC3", chocolate = "#D2CAC8"
)

bms_palette <- c(
  bms_colors$purple, bms_colors$dark_gray, bms_colors$amber, bms_colors$peach,
  bms_colors$mint, bms_colors$aqua, bms_colors$sienna, bms_colors$olive
)

scale_fill_bms  <- function(...) ggplot2::scale_fill_manual(values = bms_palette, ...)
scale_color_bms <- function(...) ggplot2::scale_color_manual(values = bms_palette, ...)
```
Usage: `ggplot(df, aes(x, fill = g)) + geom_bar() + scale_fill_bms() + theme_minimal()`.

## Testing
- `testthat` for shape and invariant checks: attrition percentages, key uniqueness, date-range sanity, row-count thresholds.
- Prefer tests on real metadata or small deterministic samples. Run test scripts via `run_r.sh` too.

## Data and privacy
- Do not output patient-level data in reports. Apply small-cell suppression (< 10).

## Related skills
- Tables: `.claude/skills/statistical-tables/SKILL.md`
- Markdown, QMD, timestamps: `.claude/skills/formatting-standards/SKILL.md`
