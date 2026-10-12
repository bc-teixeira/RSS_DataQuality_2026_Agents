---
name: statistical-tables
description: "gtsummary standards for publication-ready statistical and regression tables. Use when writing 2_Code/*Analysis*.R or *Output*.R producing tables."
---

> Applies to files matching: `2_Code/*Analysis*.R,2_Code/*Output*.R`

# Statistical Tables Standards

## gtsummary for Publication-Ready Tables

### Regression Tables
```r
# Cox, logistic, or linear models
model %>%
  tbl_regression(
    exponentiate = TRUE,
    label = variable_labels  # Custom labels, not raw names
  ) %>%
  add_global_p() %>%
  bold_p(t = 0.05) %>%
  bold_labels() %>%
  modify_footnote(
    update = all_stat_cols() ~ paste0(
      "N = ", n_obs, "; Events = ", n_events, "; C-index = ", c_index
    )
  )
```

### Survival Summary Tables
```r
list("Overall" = fit_overall, "By Group" = fit_strata) %>%
  tbl_survfit(
    probs = 0.5,  # Median
    label_header = "**Median (95% CI)**"
  ) %>%
  add_n() %>%
  bold_labels() %>%
  italicize_levels()
```

### Demographics (Table 1)
```r
data %>%
  tbl_summary(
    by = treatment_group,
    include = c(age, sex, race, bmi, cci_score),
    label = list(age ~ "Age (years)", sex ~ "Sex", race ~ "Race"),
    statistic = list(
      all_continuous() ~ "{mean} ({sd})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    missing = "ifany"
  ) %>%
  add_overall() %>%
  add_p() %>%
  bold_labels()
```

## Required Elements

- Use `tbl_regression()` for Cox/logistic/linear models (auto-formats HRs, ORs, estimates)
- Use `tbl_survfit()` for KM summaries and median survival times
- Provide custom labels for all variables (no raw column names)
- Add global p-values, N values, and model diagnostics in footnotes
- Save as `.rds` for loading in Quarto reports

## Anti-Patterns

- Do NOT create manual tables with `gt()` when gtsummary can handle it
- Do NOT use raw variable names in tables
- Do NOT omit model diagnostics or N values
- Do NOT skip small cell suppression (mask cells < 10)

## Small-Cell Suppression (MANDATORY)

All count cells with values < 10 must be masked to protect patient privacy:

```r
# Suppression helper function
suppress_small_cells <- function(tbl_obj, threshold = 10) {
  tbl_obj %>%
    modify_table_body(
      ~ .x %>%
        mutate(across(
          where(is.character),
          ~ ifelse(grepl("^[0-9]+$", .) & as.numeric(.) < threshold, "<10", .)
        ))
    )
}

# Usage
demographics_table <- data %>%
  tbl_summary(by = group, include = c(age, sex, race)) %>%
  suppress_small_cells()
```

## Saving Tables for Quarto

Save gtsummary objects as `.rds` for programmatic loading in QMD reports:

```r
# Save in analysis script
saveRDS(demographics_table, "3_Reports/Outputs/P001_Demographics/P001_table.rds")

# Load in Quarto chunk
tbl <- readRDS("3_Reports/Outputs/P001_Demographics/P001_table.rds")
tbl  # Renders automatically in QMD
```

## Model Diagnostic Footnotes by Type

| Model Type | Required Footnotes |
|------------|-------------------|
| Cox PH | N, Events, C-index, PH test p-value |
| Logistic | N, Events, AUC/C-statistic |
| Linear | N, R², Adjusted R² |
| KM survival | N at risk, Events, Median follow-up |

```r
# Cox model footnote
cox_table %>%
  modify_footnote(
    update = all_stat_cols() ~ glue::glue(
      "N = {n_obs}; Events = {n_events}; C-index = {round(c_index, 3)}; PH test p = {round(ph_p, 3)}"
    )
  )
```
