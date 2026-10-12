# =============================================================================
# 02_MDLA_DQ_Analysis.R
#
# Analysis stage: data-quality assessment of TinyEHR for the MDLA protocol
# (Stages C and D of protocol section 22), using the data-quality-evaluation
# method (Redman perfect-record score, Hoerl right-data vs data-are-right,
# Tate tiered definitions / unit-level variation).
#
# Reads  : data/derived/stage-02_cohort, stage-03_features, raw core tables
# Writes : reports/outputs/*.rds (aggregated tables only; small cells suppressed)
#
# Disclosure control: counts of 1-9 are shown as "<10" in every display column.
# Numeric columns that feed figures carry percentages only, never raw counts
# of subgroups below the threshold.
#
# Usage: bash .claude/scripts/run_r.sh code/02_MDLA_DQ_Analysis.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(lubridate)
  library(purrr)
  library(gtsummary)
})

# ---- Parameters --------------------------------------------------------------
root_raw     <- "data/raw/tinyehr_mimic_format"
dir_cohort   <- "data/derived/stage-02_cohort"
dir_features <- "data/derived/stage-03_features"
dir_out      <- "reports/outputs"

small_cell     <- 10     # CLAUDE.md: suppress counts below 10
pf_bar         <- 0.97   # Redman acceptance standard
min_subgroup   <- 30     # protocol 19: fairness subgroup minimum (test set)
min_cal_group  <- 50     # protocol 20: group-calibration fallback (validation)
seed           <- 42     # protocol 2
split_props    <- c(train = 0.70, valid = 0.15, test = 0.15)
n_predictors   <- 43
n_indicators   <- 44
uo_min_hour_cov <- 0.5   # assumption: UO "adequately captured" if >=50% of available hours have a record

dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

# ---- Helpers -------------------------------------------------------------------
read_raw <- function(path, ...) {
  readr::read_csv(file.path(root_raw, path), show_col_types = FALSE, progress = FALSE, ...)
}
save_tbl <- function(x, name) {
  saveRDS(x, file.path(dir_out, paste0(name, ".rds")))
  message("  -> saved ", name, ".rds")
}
sup <- function(n, thr = small_cell) ifelse(n > 0 & n < thr, paste0("<", thr), format(n, trim = TRUE))
sup_pct <- function(n, N, thr = small_cell, digits = 1) {
  ifelse(n > 0 & n < thr, paste0("<", thr), paste0(format(n, trim = TRUE), " (", round(100 * n / N, digits), "%)"))
}
wilson <- function(x, n, z = 1.96) {
  p <- x / n
  den <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  tibble::tibble(lo = pmax(0, centre - half), hi = pmin(1, centre + half))
}

# =============================================================================
# STEP 1. Load stage outputs
# =============================================================================
message("Step 1: Loading stage outputs ...")
cohort    <- fst::read_fst(file.path(dir_cohort, "cohort.fst")) |> tibble::as_tibble()
cohort_rds <- readRDS(file.path(dir_cohort, "attrition.rds"))
features  <- fst::read_fst(file.path(dir_features, "features_long.fst")) |> tibble::as_tibble()
obs       <- fst::read_fst(file.path(dir_features, "obs_window.fst")) |> tibble::as_tibble()
audit_rds <- readRDS(file.path(dir_features, "event_audit.rds"))
fmap      <- readRDS(file.path(dir_features, "feature_map.rds"))
n_coh     <- nrow(cohort)
message("  -> cohort: ", n_coh, "; features_long rows: ", nrow(features), "; obs: ", nrow(obs))

patients   <- read_raw("hosp/patients.csv")
admissions <- read_raw("hosp/admissions.csv")
icustays   <- read_raw("icu/icustays.csv")
transfers  <- read_raw("hosp/transfers.csv")

concepts <- features |> distinct(concept) |> pull(concept)
concept_meta <- fmap |>
  group_by(concept) |>
  summarise(group = first(group), source = paste(sort(unique(source)), collapse = " + "),
            n_itemids_mapped = n_distinct(itemid), itemids = paste(sort(unique(itemid)), collapse = ", "),
            limit_origin = first(limit_origin), lo = first(lo), hi = first(hi), .groups = "drop") |>
  bind_rows(tibble(concept = "elixhauser_count", group = "Composite", source = "diagnoses_icd",
                   n_itemids_mapped = NA_integer_, itemids = "ICD-9/10 codes (Quan Elixhauser, 31 categories)",
                   limit_origin = "n/a", lo = NA_real_, hi = NA_real_)) |>
  mutate(
    # GCS total is derived (eye + verbal + motor); the map rows carry component limits, so override
    lo = if_else(concept == "gcs_total", 3, lo),
    hi = if_else(concept == "gcs_total", 15, hi),
    limit_origin = if_else(concept == "gcs_total", "GCS total range (derived)", limit_origin),
    in_final_43 = concept != "troponin"
  )

# =============================================================================
# STEP 2. Stage A: attrition, tiers, baseline table
# =============================================================================
message("Step 2: Cohort tables ...")
attrition <- cohort_rds$attrition |>
  mutate(across(c(n_patients, n_admissions, n_icu_stays, n_patients_lost), as.integer))
tiers <- cohort_rds$tiers |>
  mutate(n_deaths_display = sup(n_deaths),
         mortality_display = if_else(n_deaths < small_cell, paste0("<", small_cell, " deaths"), paste0(mortality_pct, "%"))) |>
  select(-n_deaths, -mortality_pct)

# Baseline characteristics (gtsummary; counts <10 suppressed in the body)
elix_n <- features |> filter(concept == "elixhauser_count") |> select(stay_id, elixhauser_n = mean)
base_df <- cohort |>
  left_join(elix_n, by = "stay_id") |>
  transmute(
    age_at_icu, sex = factor(sex, c("F", "M"), c("Female", "Male")),
    age_stratum, race_group = factor(race_group, c("White", "Black", "Hispanic", "Asian", "Other")),
    insurance_group = factor(insurance_group, c("Medicare", "Medicaid", "Other/Unknown")),
    icu_type = factor(icu_type, c("MICU", "SICU", "CCU", "NICU", "TSICU", "Other")),
    los_days = los_hours / 24, elixhauser_n,
    died = factor(died, c(0, 1), c("Survived", "Died in hospital"))
  )
suppress_small <- function(tbl, thr = small_cell) {
  # Primary suppression of counts 1..thr-1 plus complementary suppression: when exactly one level
  # of a variable is hidden, the smallest remaining level is hidden too, so it cannot be recovered
  # by subtraction from the total. Overall column only (single stat_0). No backslashes in regexes:
  # gtsummary re-parses stored calls.
  gtsummary::modify_table_body(tbl, function(x) {
    x |>
      dplyr::mutate(
        .is_cnt = stringr::str_detect(stat_0, "^[0-9]+ [(][0-9.]+%[)]$") & !is.na(stat_0),
        .n = suppressWarnings(as.integer(stringr::str_extract(stat_0, "^[0-9]+"))),
        .prim = .is_cnt & .n > 0 & .n < thr
      ) |>
      dplyr::group_by(variable) |>
      dplyr::mutate(
        .min_rest = suppressWarnings(min(.n[.is_cnt & !.prim & .n > 0])),
        .comp = sum(.prim) == 1 & .is_cnt & !.prim & .n == .min_rest
      ) |>
      dplyr::ungroup() |>
      dplyr::mutate(stat_0 = dplyr::case_when(
        .prim ~ paste0("<", thr),
        .comp ~ "(suppressed)",
        TRUE ~ stat_0
      )) |>
      dplyr::select(-dplyr::starts_with("."))
  })
}
baseline_tbl <- base_df |>
  gtsummary::tbl_summary(
    include = c(age_at_icu, age_stratum, sex, race_group, insurance_group, icu_type, los_days, elixhauser_n, died),
    label = list(age_at_icu ~ "Age at ICU admission (years)", age_stratum ~ "Age stratum",
                 sex ~ "Sex", race_group ~ "Race/ethnicity (harmonised)", insurance_group ~ "Insurance",
                 icu_type ~ "ICU type (harmonised)", los_days ~ "ICU length of stay (days)",
                 elixhauser_n ~ "Elixhauser comorbidity count", died ~ "In-hospital mortality"),
    statistic = list(all_continuous() ~ "{median} ({p25}, {p75})", all_categorical() ~ "{n} ({p}%)"),
    digits = list(all_continuous() ~ 1),
    missing = "ifany", missing_text = "Missing"
  ) |>
  gtsummary::bold_labels() |>
  suppress_small() |>
  gtsummary::modify_header(label = "**Characteristic**", stat_0 = "**Index cohort**, N = {N}") |>
  gtsummary::modify_footnote(all_stat_cols() ~ paste0(
    "Median (Q1, Q3) or n (%). Cells with 1-9 patients are shown as <10; where a single level of a variable is hidden, the smallest remaining level is also hidden (complementary suppression). ",
    "Race, insurance and ICU type are analyst harmonisations of the raw TinyEHR fields."))
save_tbl(baseline_tbl, "tbl_baseline")
save_tbl(attrition, "tbl_attrition")
save_tbl(tiers, "tbl_tiers")

# =============================================================================
# STEP 3. Stage B: feature inventory (mapping, completeness, units, plausibility)
# =============================================================================
message("Step 3: Feature inventory ...")
ev <- audit_rds$event_audit |>
  group_by(concept) |>
  summarise(
    n_events_cohort = sum(n_cohort, na.rm = TRUE),
    n_pre = sum(n_cohort_pre_window, na.rm = TRUE),
    n_in = sum(n_cohort_in_window, na.rm = TRUE),
    n_post = sum(n_cohort_post_window, na.rm = TRUE),
    n_dup = sum(n_dup_exact, na.rm = TRUE),
    n_before_stay = sum(n_before_stay, na.rm = TRUE),
    n_hadm_mismatch = sum(n_hadm_mismatch, na.rm = TRUE),
    n_hadm_missing_in_window = sum(n_in_window_hadm_missing, na.rm = TRUE),
    .groups = "drop"
  ) |>
  filter(!is.na(concept))

units_seen <- obs |>
  group_by(concept) |>
  summarise(units = paste(sort(unique(coalesce(valueuom, "(blank)"))), collapse = " / "), .groups = "drop")

inv <- features |>
  group_by(concept) |>
  summarise(
    n_any_raw = sum(n_raw > 0),
    n_only_implausible = sum(n_raw > 0 & n_valid == 0),
    obs_per_pt_median = median(n_valid[n_valid > 0]),
    obs_per_pt_q1 = quantile(n_valid[n_valid > 0], 0.25, na.rm = TRUE),
    obs_per_pt_q3 = quantile(n_valid[n_valid > 0], 0.75, na.rm = TRUE),
    n_obs_valid = sum(n_valid),
    n_obs_implausible = sum(n_implausible),
    n_obs_value_missing = sum(n_value_missing),
    n_obs_unit_bad = sum(n_unit_bad),
    n_pt_implausible = sum(n_implausible > 0),
    min_valid = suppressWarnings(min(min, na.rm = TRUE)),
    max_valid = suppressWarnings(max(max, na.rm = TRUE)),
    min_raw = suppressWarnings(min(raw_min, na.rm = TRUE)),
    max_raw = suppressWarnings(max(raw_max, na.rm = TRUE)),
    n_agg_changed_by_filter = sum(!is.na(raw_min) & n_valid > 0 & (abs(raw_min - min) > 1e-9 | abs(raw_max - max) > 1e-9)),
    n_pt_prewindow_gain = sum(has_prewindow & n_valid == 0),
    n_valid = sum(n_valid > 0),   # last: this name shadows the per-stay column above
    .groups = "drop"
  ) |>
  mutate(across(c(min_valid, max_valid, min_raw, max_raw), ~ if_else(is.infinite(.x), NA_real_, .x))) |>
  left_join(concept_meta, by = "concept") |>
  left_join(units_seen, by = "concept") |>
  left_join(ev, by = "concept") |>
  mutate(
    missing_pct = 100 * (1 - n_valid / n_coh),
    status = case_when(
      n_valid == 0 ~ "Completely absent",
      n_valid == n_coh ~ "Completely observed",
      missing_pct >= 50 ~ "Sparse (>=50% missing)",
      TRUE ~ "Partially observed"
    )
  )
save_tbl(inv, "tbl_inventory")

# Concept-level distribution data for figures (values only, no identifiers)
obs_values <- obs |>
  filter(concept %in% setdiff(concepts, c("urine_output", "elixhauser_count")), unit_ok, !is.na(value_std)) |>
  select(concept, value_std, plausible)
save_tbl(obs_values, "obs_values")

# Unit report: concept x itemid x unit string
unit_report <- obs |>
  left_join(fmap |> select(source, itemid, dict_label), by = c("source", "itemid")) |>
  group_by(concept, itemid, dict_label, unit = coalesce(valueuom, "(blank)")) |>
  summarise(n_obs = n(), n_unit_ok = sum(unit_ok), .groups = "drop") |>
  filter(!is.na(itemid)) |>
  arrange(concept, itemid)
# concepts whose values come from several source codes / units
multi_source <- obs |>
  filter(unit_ok, plausible, !is.na(itemid)) |>
  group_by(concept) |>
  summarise(n_itemids = n_distinct(itemid), n_units = n_distinct(coalesce(valueuom, "(blank)")),
            n_obs = n(), .groups = "drop") |>
  filter(n_itemids > 1)
multi_source_detail <- obs |>
  filter(unit_ok, plausible, concept %in% multi_source$concept, !is.na(itemid)) |>
  count(concept, itemid, unit = coalesce(valueuom, "(blank)"), name = "n_obs") |>
  group_by(concept) |>
  mutate(share_pct = round(100 * n_obs / sum(n_obs), 1)) |>
  ungroup()
save_tbl(unit_report, "tbl_units")
save_tbl(multi_source_detail, "tbl_multisource")

# =============================================================================
# STEP 4. Stage C: conformance, relational, temporal, uniqueness
# =============================================================================
message("Step 4: Conformance / relational / temporal / uniqueness ...")
adm2 <- admissions |>
  left_join(patients |> select(subject_id, anchor_age, anchor_year, anchor_year_group, dod), by = "subject_id") |>
  mutate(
    adm_los_h = as.numeric(difftime(dischtime, admittime, units = "hours")),
    age_at_admit = anchor_age + (year(admittime) - anchor_year)
  )
rel <- bind_rows(
  tibble(domain = "Relational", check = "Admissions linked to a patient", n = nrow(admissions),
         n_fail = sum(!admissions$subject_id %in% patients$subject_id)),
  tibble(domain = "Relational", check = "ICU stays linked to an admission", n = nrow(icustays),
         n_fail = sum(!icustays$hadm_id %in% admissions$hadm_id)),
  tibble(domain = "Relational", check = "ICU stays linked to a patient", n = nrow(icustays),
         n_fail = sum(!icustays$subject_id %in% patients$subject_id)),
  tibble(domain = "Relational", check = "ICU-stay patient matches its admission's patient", n = nrow(icustays),
         n_fail = icustays |> left_join(admissions |> select(hadm_id, s2 = subject_id), by = "hadm_id") |>
           filter(!is.na(s2), s2 != subject_id) |> nrow()),
  tibble(domain = "Relational", check = "ICU stays traceable to a transfers row (stay_id = a transfer_id)", n = nrow(icustays),
         n_fail = sum(!icustays$stay_id %in% transfers$transfer_id)),
  tibble(domain = "Uniqueness", check = "Duplicate patient keys", n = nrow(patients),
         n_fail = sum(duplicated(patients$subject_id))),
  tibble(domain = "Uniqueness", check = "Duplicate admission keys", n = nrow(admissions),
         n_fail = sum(duplicated(admissions$hadm_id))),
  tibble(domain = "Uniqueness", check = "Duplicate ICU stay keys", n = nrow(icustays),
         n_fail = sum(duplicated(icustays$stay_id))),
  tibble(domain = "Uniqueness", check = "Index ICU stays per patient > 1 in analytical cohort", n = n_coh,
         n_fail = sum(duplicated(cohort$subject_id))),
  tibble(domain = "Temporal", check = "ICU outtime later than intime", n = nrow(icustays),
         n_fail = sum(icustays$outtime <= icustays$intime)),
  tibble(domain = "Temporal", check = "ICU LOS (days) agrees with outtime - intime (tolerance 0.01 d)", n = nrow(icustays),
         n_fail = sum(abs(icustays$los - as.numeric(difftime(icustays$outtime, icustays$intime, units = "days"))) > 0.01)),
  tibble(domain = "Temporal", check = "Hospital discharge later than admission", n = nrow(admissions),
         n_fail = sum(admissions$dischtime < admissions$admittime, na.rm = TRUE)),
  tibble(domain = "Temporal", check = "ICU stay starts inside the admission interval", n = nrow(icustays),
         n_fail = icustays |> left_join(admissions |> select(hadm_id, admittime, dischtime), by = "hadm_id") |>
           filter(intime < admittime | intime > dischtime) |> nrow()),
  tibble(domain = "Temporal", check = "ICU stay ends inside the admission interval", n = nrow(icustays),
         n_fail = icustays |> left_join(admissions |> select(hadm_id, admittime, dischtime), by = "hadm_id") |>
           filter(outtime > dischtime | outtime < admittime) |> nrow()),
  tibble(domain = "Conformance", check = "anchor_age within 18-91 (cap at 91 for >89)", n = nrow(patients),
         n_fail = sum(patients$anchor_age < 18 | patients$anchor_age > 91)),
  tibble(domain = "Conformance", check = "Age at ICU admission derivable and 18-120 (index cohort)", n = n_coh,
         n_fail = sum(is.na(cohort$age_at_icu) | cohort$age_at_icu < 18 | cohort$age_at_icu > 120)),
  tibble(domain = "Conformance", check = "Age at admission derivable and 18-120 (all admissions)", n = nrow(adm2),
         n_fail = sum(is.na(adm2$age_at_admit) | adm2$age_at_admit < 18 | adm2$age_at_admit > 120)),
  tibble(domain = "Conformance", check = "Admission year within 10 years of anchor_year (date-shift coherence)", n = nrow(adm2),
         n_fail = sum(abs(year(adm2$admittime) - adm2$anchor_year) > 10)),
  tibble(domain = "Conformance", check = "hospital_expire_flag in {0, 1}", n = nrow(admissions),
         n_fail = sum(!admissions$hospital_expire_flag %in% c(0, 1))),
  tibble(domain = "Conformance", check = "Gender in {F, M}", n = nrow(patients), n_fail = sum(!patients$gender %in% c("F", "M")))
)

icu_overrun <- icustays |>
  left_join(admissions |> select(hadm_id, dischtime), by = "hadm_id") |>
  mutate(over_h = as.numeric(difftime(outtime, dischtime, units = "hours"))) |>
  filter(over_h > 0) |>
  summarise(n = n(), median_h = median(over_h), max_h = max(over_h), n_gt_24h = sum(over_h > 24))
save_tbl(icu_overrun, "tbl_icu_overrun")

# Outcome consistency on the index admission (protocol question 5)
out_chk <- cohort |>
  mutate(
    flag_without_deathtime = died == 1 & is.na(deathtime),
    deathtime_without_flag = died == 0 & !is.na(deathtime),
    died_location_mismatch = (died == 1) != (discharge_location == "DIED"),
    dod_mismatch = !is.na(dod) & died == 1 & (as.Date(dod) < as.Date(admittime) | as.Date(dod) > as.Date(dischtime) + 1),
    dod_in_hosp_but_alive = !is.na(dod) & died == 0 & as.Date(dod) >= as.Date(admittime) & as.Date(dod) <= as.Date(dischtime)
  )
rel <- bind_rows(
  rel,
  tibble(domain = "Conformance", check = "Mortality flag = 1 has a deathtime (index admission)", n = sum(cohort$died == 1),
         n_fail = sum(out_chk$flag_without_deathtime)),
  tibble(domain = "Conformance", check = "Mortality flag = 0 has no deathtime (index admission)", n = sum(cohort$died == 0),
         n_fail = sum(out_chk$deathtime_without_flag)),
  tibble(domain = "Conformance", check = "Mortality flag agrees with discharge_location = DIED", n = n_coh,
         n_fail = sum(out_chk$died_location_mismatch)),
  tibble(domain = "Conformance", check = "Date of death (dod) falls in the index admission when flag = 1", n = sum(cohort$died == 1),
         n_fail = sum(out_chk$dod_mismatch)),
  tibble(domain = "Conformance", check = "Survivors without a date of death inside the index admission", n = sum(cohort$died == 0),
         n_fail = sum(out_chk$dod_in_hosp_but_alive))
)

# Demographic consistency across admissions of the same patient
race_incons <- admissions |>
  group_by(subject_id) |>
  summarise(n_adm = n(), n_race = n_distinct(race), .groups = "drop") |>
  summarise(n_multi_adm = sum(n_adm > 1), n_inconsistent = sum(n_adm > 1 & n_race > 1))
rel <- bind_rows(
  rel,
  tibble(domain = "Consistency", check = "Race recorded identically across a patient's admissions (multi-admission patients)",
         n = race_incons$n_multi_adm, n_fail = race_incons$n_inconsistent)
)
rel <- rel |>
  mutate(n_fail_display = sup(n_fail), pct_fail = round(100 * n_fail / n, 1),
         status = case_when(n_fail == 0 ~ "Pass", pct_fail < 3 ~ "Minor", TRUE ~ "Issue"))
save_tbl(rel, "tbl_integrity")

# Temporal / window report per concept (event counts, outside-window shares)
temporal <- inv |>
  filter(!is.na(n_events_cohort)) |>
  transmute(concept, group, n_events_cohort, n_pre, n_in, n_post,
            pct_in_window = round(100 * n_in / n_events_cohort, 1),
            n_before_stay, n_hadm_mismatch, n_hadm_missing_in_window, n_dup)
save_tbl(temporal, "tbl_temporal")

# Window coverage: ICU stays shorter than 24 h only offer a truncated window
window_cov <- cohort |>
  summarise(n = n(), n_short = sum(los_hours < 24), pct_short = round(100 * mean(los_hours < 24), 1),
            median_los_h = median(los_hours), median_window_h = median(window_hours_available),
            n_under_12 = sum(los_hours < 12))
save_tbl(window_cov, "tbl_window_coverage")

# Urine output capture (protocol 10.1)
uo <- features |>
  filter(concept == "urine_output") |>
  left_join(cohort |> select(stay_id, window_hours_available), by = "stay_id") |>
  mutate(hours_avail = ceiling(window_hours_available),
         hour_cov = if_else(is.na(n_hours_with_record), 0, n_hours_with_record / hours_avail),
         adequate = hour_cov >= uo_min_hour_cov)
uo_neg <- read_raw("icu/outputevents.csv", col_select = c(itemid, value, valueuom)) |>
  filter(itemid %in% fmap$itemid[fmap$concept == "urine_output"]) |>
  summarise(n_records = n(), n_negative = sum(value < 0, na.rm = TRUE), n_missing_value = sum(is.na(value)),
            n_non_ml = sum(tolower(valueuom) != "ml" | is.na(valueuom)))
uo_tbl <- uo |>
  summarise(
    n_stays = n(), n_with_record = sum(n_valid > 0),
    median_hours_covered_pct = round(100 * median(hour_cov), 1),
    n_adequate = sum(adequate), pct_adequate = round(100 * mean(adequate), 1),
    median_first_record_h = round(median(first_obs_h, na.rm = TRUE), 1),
    median_total_ml = round(median(total, na.rm = TRUE)),
    n_zero_total = sum(total == 0, na.rm = TRUE)
  ) |>
  bind_cols(uo_neg)
save_tbl(uo_tbl, "tbl_urine_output")

# Elixhauser reconstruction (protocol 10.2, question 18)
elix_tbl <- audit_rds$elix_summary |>
  mutate(pct_with_decimal = round(100 * n_with_decimal / n_dx_rows, 1),
         pct_in_dict = round(100 * n_dx_in_dict / n_dx_rows, 1))
save_tbl(elix_tbl, "tbl_elixhauser")
save_tbl(audit_rds$gcs, "tbl_gcs")

# =============================================================================
# STEP 5. Perfect-record score, Pareto, variation across ICU types
# =============================================================================
message("Step 5: Perfect-record scoring ...")
unknown_race <- c("UNKNOWN", "UNABLE TO OBTAIN", "PATIENT DECLINED TO ANSWER")
cde_phys <- c("heart_rate", "map", "sbp", "resp_rate", "spo2", "temperature", "gcs_total",
              "creatinine", "urine_output", "elixhauser_count")
cde_index <- c("age", "sex", "race", "outcome", "icu_timestamps")

index_err <- cohort |>
  transmute(
    stay_id,
    age = is.na(age_at_icu) | age_at_icu < 18 | age_at_icu > 120,
    sex = !sex %in% c("F", "M"),
    race = is.na(race) | race %in% unknown_race,
    outcome = (died == 1 & is.na(deathtime)) | (died == 0 & !is.na(deathtime)) | ((died == 1) != (discharge_location == "DIED")),
    icu_timestamps = outtime <= intime | intime < admittime | intime > dischtime
  ) |>
  pivot_longer(-stay_id, names_to = "cde", values_to = "error") |>
  mutate(error_type = if_else(error, if_else(cde == "race", "Missing / unknown", "Inconsistent or invalid"), NA_character_))
phys_err <- features |>
  filter(concept %in% cde_phys) |>
  transmute(
    stay_id, cde = concept,
    error = n_valid == 0,
    error_type = case_when(
      n_valid > 0 ~ NA_character_,
      n_unit_bad > 0 & n_raw == n_unit_bad ~ "Unit mismatch only",
      n_raw > 0 ~ "Implausible / non-numeric only",
      TRUE ~ "Missing (no observation in window)"
    )
  )
err_long <- bind_rows(index_err, phys_err)
score_sets <- list(
  "Index record (5 CDEs)" = cde_index,
  "Index + 7 vital signs (12 CDEs)" = c(cde_index, "heart_rate", "map", "sbp", "resp_rate", "spo2", "temperature", "gcs_total"),
  "Full analytical set (15 CDEs)" = c(cde_index, cde_phys),
  "Full set excluding race (14 CDEs)" = setdiff(c(cde_index, cde_phys), "race")
)
perfect <- imap_dfr(score_sets, function(cdes, nm) {
  per_rec <- err_long |> filter(cde %in% cdes) |> group_by(stay_id) |> summarise(perfect = !any(error), .groups = "drop")
  x <- sum(per_rec$perfect); n <- nrow(per_rec)
  bind_cols(tibble(cde_set = nm, n_cde = length(cdes), n_records = n, n_perfect = x,
                   perfect_pct = 100 * x / n, meets_97 = x / n >= pf_bar),
            wilson(x, n) |> mutate(across(everything(), ~ 100 * .x)) |> rename(ci_lo = lo, ci_hi = hi))
})
pareto <- err_long |>
  filter(error) |>
  count(cde, error_type, name = "n_errors") |>
  mutate(share_pct = round(100 * n_errors / sum(n_errors), 1)) |>
  arrange(desc(n_errors)) |>
  mutate(cum_share_pct = cumsum(share_pct), n_display = sup(n_errors))
cde_error_rate <- err_long |>
  group_by(cde) |>
  summarise(n_err = sum(error), err_pct = round(100 * mean(error), 1), .groups = "drop") |>
  arrange(desc(n_err))
save_tbl(perfect, "tbl_perfect_record")
save_tbl(pareto, "tbl_pareto")
save_tbl(cde_error_rate, "tbl_cde_error")
message("  -> Perfect-record (full set): ", round(perfect$perfect_pct[perfect$cde_set == "Full analytical set (15 CDEs)"], 1), "%")

# Variation across ICU types (Tate: unit-level, not just average)
rec_full <- err_long |>
  filter(cde %in% score_sets[["Full analytical set (15 CDEs)"]]) |>
  group_by(stay_id) |>
  summarise(perfect = !any(error), n_err = sum(error), .groups = "drop") |>
  left_join(cohort |> select(stay_id, icu_type, sex, race_group, insurance_group), by = "stay_id")
by_unit <- rec_full |>
  group_by(icu_type) |>
  summarise(n = n(), x = sum(perfect), .groups = "drop") |>
  mutate(wilson(x, n) |> mutate(across(everything(), ~ 100 * .x)),
         perfect_pct = 100 * x / n, shown = n >= small_cell,
         n_display = sup(n),
         perfect_pct = if_else(shown, perfect_pct, NA_real_),
         lo = if_else(shown, lo, NA_real_), hi = if_else(shown, hi, NA_real_)) |>
  select(icu_type, n_display, perfect_pct, lo, hi, shown)
save_tbl(by_unit, "tbl_perfect_by_icu")

# =============================================================================
# STEP 6. Stage D: missingness audit
# =============================================================================
message("Step 6: Missingness audit ...")
miss <- features |>
  filter(concept != "elixhauser_count" | TRUE) |>
  transmute(stay_id, concept, miss = as.integer(n_valid == 0)) |>
  left_join(cohort |> select(stay_id, sex, race_group, insurance_group, icu_type), by = "stay_id")

miss_overall <- miss |>
  group_by(concept) |>
  summarise(n_missing = sum(miss), pct_missing = 100 * mean(miss), .groups = "drop") |>
  left_join(concept_meta |> select(concept, group), by = "concept")

subgroup_miss <- map_dfr(c("sex", "race_group", "insurance_group", "icu_type"), function(v) {
  miss |>
    group_by(concept, level = as.character(.data[[v]])) |>
    summarise(n = n(), pct_missing = 100 * mean(miss), .groups = "drop") |>
    mutate(variable = v)
}) |>
  mutate(shown = n >= small_cell,
         pct_missing = if_else(shown, pct_missing, NA_real_),
         n = if_else(shown, n, NA_integer_))
group_sizes <- map_dfr(c("sex", "race_group", "insurance_group", "icu_type"), function(v) {
  cohort |> mutate(level = as.character(.data[[if (v == "sex") "sex" else v]])) |>
    count(level, name = "n") |> mutate(variable = v)
}) |>
  mutate(n_display = sup(n), shown = n >= small_cell) |>
  select(-n)
save_tbl(miss_overall, "tbl_miss_overall")
save_tbl(subgroup_miss, "tbl_miss_subgroup")
save_tbl(group_sizes, "tbl_group_sizes")

# Missingness correlation matrix (phi) across non-constant indicators
ind_wide <- miss |> select(stay_id, concept, miss) |> pivot_wider(names_from = concept, values_from = miss)
nonconst <- names(ind_wide)[-1][map_lgl(ind_wide[-1], ~ n_distinct(.x) > 1)]
phi <- stats::cor(ind_wide[nonconst])
phi_long <- as.data.frame(as.table(phi)) |>
  setNames(c("x", "y", "phi")) |>
  as_tibble()
const_status <- tibble(
  concept = names(ind_wide)[-1],
  constant = !names(ind_wide)[-1] %in% nonconst,
  all_missing = map_lgl(ind_wide[-1], ~ all(.x == 1)),
  all_observed = map_lgl(ind_wide[-1], ~ all(.x == 0))
)
save_tbl(phi_long, "tbl_miss_phi")
save_tbl(const_status, "tbl_miss_constant")

# Protocol indicator bookkeeping (44 nominal vs distinct measurable)
indicator_book <- tibble(
  item = c("Protocol: candidate features (20 vital + 22 lab + 2 composite)", "Protocol: indicators incl. troponin",
           "Distinct measurable concepts here (7 vitals + 22 labs + 2 composites)",
           "Vital-sign domains behind the 20 vital features",
           "Concepts with constant missingness in this cohort (untestable)",
           "Concepts with variable missingness (testable)"),
  value = c(44, 44, length(concepts), 7, sum(const_status$constant), length(nonconst))
)
save_tbl(indicator_book, "tbl_indicator_book")

# Chi-square feasibility vs race (protocol step 3), no p-values reported
race_levels <- cohort |> count(race_group) |> filter(n > 0)
chi_feas <- map_dfr(nonconst, function(cn) {
  d <- miss |> filter(concept == cn)
  tb <- table(d$miss, d$race_group)
  tb <- tb[, colSums(tb) > 0, drop = FALSE]
  if (ncol(tb) < 2 || nrow(tb) < 2) return(tibble(concept = cn, pct_cells_lt5 = NA_real_))
  ex <- suppressWarnings(stats::chisq.test(tb)$expected)
  tibble(concept = cn, pct_cells_lt5 = 100 * mean(ex < 5))
})
chi_summary <- tibble(
  n_testable = nrow(chi_feas),
  n_with_gt20pct_cells_lt5 = sum(chi_feas$pct_cells_lt5 > 20, na.rm = TRUE),
  median_pct_cells_lt5 = median(chi_feas$pct_cells_lt5, na.rm = TRUE),
  n_race_groups_gt0 = nrow(race_levels),
  n_race_groups_ge10 = sum(race_levels$n >= small_cell),
  n_bonferroni_protocol = 43
)
save_tbl(chi_summary, "tbl_chi_feasibility")

# =============================================================================
# STEP 7. Fitness for purpose: MDLA feasibility
# =============================================================================
message("Step 7: Feasibility of the MDLA workflow ...")
set.seed(seed)
split_df <- cohort |>
  select(stay_id, died, race_group, sex) |>
  group_by(died) |>
  mutate(u = sample(row_number()),
         split = case_when(u <= round(split_props["train"] * n()) ~ "train",
                           u <= round((split_props["train"] + split_props["valid"]) * n()) ~ "valid",
                           TRUE ~ "test")) |>
  ungroup()
split_tbl <- split_df |>
  count(split, name = "n") |>
  left_join(split_df |> group_by(split) |> summarise(deaths = sum(died), .groups = "drop"), by = "split") |>
  mutate(split = factor(split, c("train", "valid", "test"))) |>
  arrange(split) |>
  mutate(n_display = sup(n), deaths_display = sup(deaths))
n_deaths <- sum(cohort$died)
n_surv <- n_coh - n_deaths
race_n <- cohort |> count(race_group)
ins_n <- cohort |> count(insurance_group)
trop <- inv |> filter(concept == "troponin")
test_n <- split_tbl$n[split_tbl$split == "test"]
valid_n <- split_tbl$n[split_tbl$split == "valid"]
feas <- tribble(
  ~requirement, ~protocol, ~available, ~verdict,
  "Final analytical cohort size", "50,827 ICU stays", format(n_coh), "Not comparable (0.14% of published N)",
  "In-hospital deaths (events)", "Thousands (mortality-stratified split)", sup(n_deaths), if_else(n_deaths >= 50, "Adequate", "Inadequate"),
  "Events per predictor (43 clinical)", ">= 10 (rule of thumb)", sprintf("<= %.2f", (small_cell - 1) / n_predictors), "Inadequate",
  "Events per input (87 with indicators)", ">= 10 (rule of thumb)", sprintf("<= %.2f", (small_cell - 1) / (n_predictors + n_indicators)), "Inadequate",
  "5-fold stratified CV needs >= 5 events", "5 folds", paste0(sup(n_deaths), " events"), if_else(n_deaths >= 5 * 3, "Feasible", "Not feasible in practice"),
  "70/15/15 split: deaths in validation + test", "Both > 0", paste0(sup(sum(split_tbl$deaths[split_tbl$split != "train"])), " combined"),
  if_else(all(split_tbl$deaths[split_tbl$split != "train"] > 0), "Marginal", "Not feasible (AUROC undefined)"),
  "Fairness subgroup >= 30 in test set", "n >= 30", paste0("test n = ", test_n), if_else(test_n >= min_subgroup, "Possible", "Not feasible"),
  "Race groups with >= 10 patients", "5 groups", paste0(sum(race_n$n >= small_cell), " of ", nrow(race_n), " present (", 5 - nrow(race_n), " absent)"), "Inadequate for multinomial race model",
  "Group-conditional calibration (>= 50 validation obs)", "n >= 50", paste0("validation n = ", valid_n), "All groups fall back to global",
  "Troponin 100% missing (excluded by authors)", "100% missing in training", sprintf("%.1f%% missing here", trop$missing_pct), "Not reproduced (data-dependent)",
  "Association tests (43, Bonferroni)", "43 tests, race (5 groups)", paste0(chi_summary$n_testable, " testable indicators"), "Sparse cells; descriptive only",
  "External validation (eICU-CRD)", "eICU-CRD v2.0", "Not available", "Out of scope"
)
save_tbl(feas, "tbl_feasibility")
save_tbl(split_tbl, "tbl_split")

# =============================================================================
# STEP 8. Pedigree-derived fitness summary numbers for the report
# =============================================================================
message("Step 8: Headline numbers ...")
headline <- list(
  n_cohort = n_coh,
  deaths_display = sup(n_deaths),
  attrition_final_pct = attrition$pct_patients_remaining[nrow(attrition)],
  perfect_full = perfect |> filter(str_detect(cde_set, "Full")) |> as.list(),
  n_concepts = length(concepts),
  n_absent = sum(inv$status == "Completely absent"),
  n_complete = sum(inv$status == "Completely observed"),
  n_sparse = sum(inv$status == "Sparse (>=50% missing)"),
  n_partial = sum(inv$status == "Partially observed"),
  generated = format(Sys.Date(), "%Y-%m-%d"),
  generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)
save_tbl(headline, "headline")
message("Done.")
