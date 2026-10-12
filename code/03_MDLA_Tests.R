# =============================================================================
# 03_MDLA_Tests.R
# testthat invariants for the MDLA data-quality pipeline (01 and 02 outputs).
# Usage: bash .claude/scripts/run_r.sh code/03_MDLA_Tests.R
# =============================================================================
suppressPackageStartupMessages({
  library(testthat)
  library(dplyr)
})

dir_cohort   <- "data/derived/stage-02_cohort"
dir_features <- "data/derived/stage-03_features"
dir_out      <- "reports/outputs"
window_hours <- 24
min_los_hours <- 4
min_age_years <- 18
small_cell <- 10

cohort   <- fst::read_fst(file.path(dir_cohort, "cohort.fst"))
features <- fst::read_fst(file.path(dir_features, "features_long.fst"))
obs      <- fst::read_fst(file.path(dir_features, "obs_window.fst"))
attr_rds <- readRDS(file.path(dir_cohort, "attrition.rds"))
r <- function(n) readRDS(file.path(dir_out, paste0(n, ".rds")))

message("Running invariants ...")
res <- test_that("cohort invariants (protocol 4)", {
  expect_equal(anyDuplicated(cohort$subject_id), 0L)
  expect_equal(anyDuplicated(cohort$stay_id), 0L)
  expect_true(all(cohort$age_at_icu >= min_age_years))
  expect_true(all(cohort$los_hours >= min_los_hours))
  expect_false(anyNA(cohort$died))
  expect_true(all(cohort$died %in% c(0, 1)))
  expect_true(all(cohort$adm_rank == 1))
  expect_true(all(cohort$stay_rank_adm == 1))
})
test_that("attrition is monotone non-increasing and ends at the cohort size", {
  a <- attr_rds$attrition
  expect_true(all(diff(a$n_patients) <= 0))
  expect_equal(a$n_patients[nrow(a)], nrow(cohort))
})
test_that("all predictor observations lie in the 24 h window (protocol 5)", {
  expect_true(all(obs$rel_h >= 0 & obs$rel_h <= window_hours))
  expect_true(all(obs$stay_id %in% cohort$stay_id))
})
test_that("features grid is complete: every stay x every concept exactly once", {
  expect_equal(anyDuplicated(features[c("stay_id", "concept")]), 0L)
  expect_equal(nrow(features), nrow(cohort) * dplyr::n_distinct(features$concept))
})
test_that("aggregates only come from valid observations", {
  v <- features |> filter(n_valid == 0)
  expect_true(all(is.na(v$min) | v$concept == "elixhauser_count"))
})
test_that("plausibility limits are applied (creatinine 0.1-30, pH 6.5-8.0 from the protocol)", {
  cr <- obs |> filter(concept == "creatinine", plausible)
  ph <- obs |> filter(concept == "ph", plausible)
  expect_true(all(cr$value_std >= 0.1 & cr$value_std <= 30))
  expect_true(all(ph$value_std >= 6.5 & ph$value_std <= 8))
})
test_that("missingness indicators are created before imputation (no imputed values in features)", {
  expect_true(all(features$n_valid >= 0))
  expect_false(any(features$n_valid == 0 & !is.na(features$mean) & features$concept != "elixhauser_count"))
})
test_that("small-cell suppression: no displayed count of 1-9 in report tables", {
  integ <- r("tbl_integrity")
  expect_false(any(integ$n_fail_display %in% as.character(1:9)))
  pareto <- r("tbl_pareto")
  expect_false(any(pareto$n_display %in% as.character(1:9)))
  split <- r("tbl_split")
  expect_false(any(split$n_display %in% as.character(1:9) | split$deaths_display %in% as.character(1:9)))
  sub <- r("tbl_miss_subgroup")
  expect_true(all(is.na(sub$n) | sub$n >= small_cell))
  base <- as.data.frame(gtsummary::as_tibble(r("tbl_baseline"), col_labels = FALSE))
  cells <- unlist(base[-1])
  cnt <- stringr::str_extract(cells[which(stringr::str_detect(cells, "^[0-9]+ [(][0-9.]+%[)]$"))], "^[0-9]+")
  expect_true(all(as.integer(cnt) >= small_cell | as.integer(cnt) == 0))
  tr <- r("tbl_tiers")
  expect_false(any(tr$n_deaths_display %in% as.character(1:9)))
})
test_that("perfect-record score is a proportion with an ordered interval", {
  p <- r("tbl_perfect_record")
  expect_true(all(p$perfect_pct >= 0 & p$perfect_pct <= 100))
  expect_true(all(p$ci_lo <= p$perfect_pct & p$perfect_pct <= p$ci_hi))
})
message("All invariants evaluated.")
