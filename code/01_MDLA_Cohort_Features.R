# =============================================================================
# 01_MDLA_Cohort_Features.R
#
# Processing stage for the MDLA protocol reproduction on TinyEHR
# (protocol/MDLA_MIMIC_IV_Reproduction_Protocol.md).
#
#   Stage A  cohort construction + attrition + tiered-definition sensitivity
#   Stage B  first-24-hour feature extraction (unit -> plausibility -> aggregate)
#   Stage B' event-level audit counts (temporal, duplicates, linkage, units)
#
# Pipeline order follows protocol section 11:
#   raw value -> unit validation -> plausibility validation -> aggregation
#   -> missingness indicator
#
# Outputs (patient-level files stay local and are never rendered in the report):
#   data/derived/stage-02_cohort/cohort.fst
#   data/derived/stage-02_cohort/attrition.rds
#   data/derived/stage-03_features/features_long.fst
#   data/derived/stage-03_features/obs_window.fst
#   data/derived/stage-03_features/event_audit.rds
#   data/derived/stage-03_features/feature_map.rds
#
# Usage: bash .claude/scripts/run_r.sh code/01_MDLA_Cohort_Features.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(lubridate)
  library(purrr)
})

# ---- Parameters --------------------------------------------------------------
root_raw      <- "data/raw/tinyehr_mimic_format"
dir_cohort    <- "data/derived/stage-02_cohort"
dir_features  <- "data/derived/stage-03_features"

min_age_years <- 18   # protocol 4.1 (1)
min_los_hours <- 4    # protocol 4.1 (2)
window_hours  <- 24   # protocol 5
lookback_hours <- 24  # sensitivity only: pre-ICU look-back for labs (not in protocol)

dir.create(dir_cohort, recursive = TRUE, showWarnings = FALSE)
dir.create(dir_features, recursive = TRUE, showWarnings = FALSE)

# ---- Feature map (analyst mapping; protocol gives no item IDs, see section 27) --
# Plausibility limits: protocol gives only creatinine (0.1-30) and pH (6.5-8.0);
# every other limit is an analyst assumption and must be replaced by the
# authors' released limits for an exact reproduction.
feature_map <- tribble(
  ~concept,        ~group,       ~source,       ~itemid, ~unit_regex,  ~lo,   ~hi,   ~limit_origin,
  # vitals (chartevents)
  "heart_rate",    "Vital",      "chartevents", 220045,  "^bpm$",      0,     300,   "assumed",
  "sbp",           "Vital",      "chartevents", 220050,  "^mmHg$",     20,    300,   "assumed",
  "sbp",           "Vital",      "chartevents", 220179,  "^mmHg$",     20,    300,   "assumed",
  "map",           "Vital",      "chartevents", 220052,  "^mmHg$",     10,    250,   "assumed",
  "map",           "Vital",      "chartevents", 220181,  "^mmHg$",     10,    250,   "assumed",
  "resp_rate",     "Vital",      "chartevents", 220210,  "^insp/min$", 0,     80,    "assumed",
  "resp_rate",     "Vital",      "chartevents", 224690,  "^insp/min$", 0,     80,    "assumed",
  "spo2",          "Vital",      "chartevents", 220277,  "^%$",        0,     100,   "assumed",
  "temperature",   "Vital",      "chartevents", 223762,  "C$",         25,    45,    "assumed",
  "temperature",   "Vital",      "chartevents", 223761,  "F$",         25,    45,    "assumed (after F to C)",
  "gcs_total",     "Vital",      "chartevents", 220739,  NA,           1,     4,     "GCS eye component",
  "gcs_total",     "Vital",      "chartevents", 223900,  NA,           1,     5,     "GCS verbal component",
  "gcs_total",     "Vital",      "chartevents", 223901,  NA,           1,     6,     "GCS motor component",
  # laboratory (labevents, blood)
  "creatinine",    "Laboratory", "labevents",   50912,   "mg/dL",      0.1,   30,    "protocol",
  "creatinine",    "Laboratory", "labevents",   52546,   "mg/dL",      0.1,   30,    "protocol",
  "creatinine",    "Laboratory", "labevents",   52024,   "mg/dL",      0.1,   30,    "protocol",
  "bun",           "Laboratory", "labevents",   51006,   "mg/dL",      1,     300,   "assumed",
  "bun",           "Laboratory", "labevents",   52647,   "mg/dL",      1,     300,   "assumed",
  "lactate",       "Laboratory", "labevents",   50813,   "mmol/L",     0.1,   30,    "assumed",
  "lactate",       "Laboratory", "labevents",   52442,   "mmol/L",     0.1,   30,    "assumed",
  "lactate",       "Laboratory", "labevents",   53154,   "mmol/L",     0.1,   30,    "assumed",
  "hemoglobin",    "Laboratory", "labevents",   51222,   "g/dL",       1,     25,    "assumed",
  "hemoglobin",    "Laboratory", "labevents",   50811,   "g/dL",       1,     25,    "assumed",
  "hematocrit",    "Laboratory", "labevents",   51221,   "^%$",        5,     70,    "assumed",
  "hematocrit",    "Laboratory", "labevents",   50810,   "^%$",        5,     70,    "assumed",
  "platelets",     "Laboratory", "labevents",   51265,   "K/uL",       1,     2000,  "assumed",
  "wbc",           "Laboratory", "labevents",   51301,   "K/uL",       0.1,   500,   "assumed",
  "wbc",           "Laboratory", "labevents",   51300,   "K/uL",       0.1,   500,   "assumed",
  "sodium",        "Laboratory", "labevents",   50983,   "mEq/L",      90,    190,   "assumed",
  "sodium",        "Laboratory", "labevents",   50824,   "mEq/L",      90,    190,   "assumed",
  "sodium",        "Laboratory", "labevents",   52455,   "mEq/L",      90,    190,   "assumed",
  "sodium",        "Laboratory", "labevents",   52623,   "mEq/L",      90,    190,   "assumed",
  "potassium",     "Laboratory", "labevents",   50971,   "mEq/L",      1.5,   10,    "assumed",
  "potassium",     "Laboratory", "labevents",   50822,   "mEq/L",      1.5,   10,    "assumed",
  "potassium",     "Laboratory", "labevents",   52452,   "mEq/L",      1.5,   10,    "assumed",
  "potassium",     "Laboratory", "labevents",   52610,   "mEq/L",      1.5,   10,    "assumed",
  "bicarbonate",   "Laboratory", "labevents",   50882,   "mEq/L",      2,     60,    "assumed",
  "chloride",      "Laboratory", "labevents",   50902,   "mEq/L",      50,    150,   "assumed",
  "chloride",      "Laboratory", "labevents",   50806,   "mEq/L",      50,    150,   "assumed",
  "chloride",      "Laboratory", "labevents",   52434,   "mEq/L",      50,    150,   "assumed",
  "chloride",      "Laboratory", "labevents",   52535,   "mEq/L",      50,    150,   "assumed",
  "glucose",       "Laboratory", "labevents",   50931,   "mg/dL",      10,    2000,  "assumed",
  "glucose",       "Laboratory", "labevents",   50809,   "mg/dL",      10,    2000,  "assumed",
  "glucose",       "Laboratory", "labevents",   52027,   "mg/dL",      10,    2000,  "assumed",
  "glucose",       "Laboratory", "labevents",   52569,   "mg/dL",      10,    2000,  "assumed",
  "pao2",          "Laboratory", "labevents",   50821,   "mm ?Hg",     10,    800,   "assumed",
  "paco2",         "Laboratory", "labevents",   50818,   "mm ?Hg",     5,     200,   "assumed",
  "ph",            "Laboratory", "labevents",   50820,   "unit",       6.5,   8.0,   "protocol",
  "alt",           "Laboratory", "labevents",   50861,   "IU/L",       1,     10000, "assumed",
  "alt",           "Laboratory", "labevents",   53084,   "IU/L",       1,     10000, "assumed",
  "ast",           "Laboratory", "labevents",   50878,   "IU/L",       1,     10000, "assumed",
  "ast",           "Laboratory", "labevents",   53088,   "IU/L",       1,     10000, "assumed",
  "bilirubin",     "Laboratory", "labevents",   50885,   "mg/dL",      0.1,   70,    "assumed",
  "bilirubin",     "Laboratory", "labevents",   53089,   "mg/dL",      0.1,   70,    "assumed",
  "albumin",       "Laboratory", "labevents",   50862,   "g/dL",       0.5,   7,     "assumed",
  "albumin",       "Laboratory", "labevents",   53085,   "g/dL",       0.5,   7,     "assumed",
  "albumin",       "Laboratory", "labevents",   52022,   "g/dL",       0.5,   7,     "assumed",
  "inr",           "Laboratory", "labevents",   51237,   NA,           0.5,   20,    "assumed",
  "ptt",           "Laboratory", "labevents",   51275,   "sec",        10,    300,   "assumed",
  "ptt",           "Laboratory", "labevents",   52923,   "sec",        10,    300,   "assumed",
  "troponin",      "Laboratory", "labevents",   51003,   "ng/mL",      0,     1000,  "assumed",
  "troponin",      "Laboratory", "labevents",   51002,   "ng/mL",      0,     1000,  "assumed",
  "troponin",      "Laboratory", "labevents",   52642,   "ng/mL",      0,     1000,  "assumed",
  "troponin",      "Laboratory", "chartevents", 227429,  "ng/mL",      0,     1000,  "assumed",
  # urine output (outputevents; unit mL)
  "urine_output",  "Composite",  "outputevents", 226559,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226560,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226561,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226563,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226564,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226565,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226567,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226557,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226558,  "^mL$",      0,     5000,  "assumed (per record)",
  "urine_output",  "Composite",  "outputevents", 226584,  "^mL$",      0,     5000,  "assumed (per record)"
)
# Concepts that need special handling (derived, not item-level)
concept_levels <- c(
  "heart_rate", "sbp", "map", "resp_rate", "spo2", "temperature", "gcs_total",
  "creatinine", "bun", "lactate", "hemoglobin", "hematocrit", "platelets", "wbc",
  "sodium", "potassium", "bicarbonate", "chloride", "glucose", "pao2", "paco2",
  "ph", "alt", "ast", "bilirubin", "albumin", "inr", "ptt", "troponin",
  "urine_output", "elixhauser_count"
)

# ---- Helpers -------------------------------------------------------------------
read_raw <- function(path, ...) {
  readr::read_csv(file.path(root_raw, path), show_col_types = FALSE, progress = FALSE, ...)
}
safe_stat <- function(x, f) if (length(x) == 0) NA_real_ else f(x)

# =============================================================================
# STEP 1. Load core tables
# =============================================================================
message("Step 1: Loading core tables ...")
patients   <- read_raw("hosp/patients.csv")
admissions <- read_raw("hosp/admissions.csv")
icustays   <- read_raw("icu/icustays.csv")
d_items    <- read_raw("icu/d_items.csv")
d_labitems <- read_raw("hosp/d_labitems.csv")
message("  -> patients: ", nrow(patients), "; admissions: ", nrow(admissions),
        "; ICU stays: ", nrow(icustays))

# Verify the analyst mapping against the dictionaries (conformance of the mapping itself)
dict <- bind_rows(
  d_labitems |> transmute(source = "labevents", itemid, dict_label = label, dict_fluid = fluid),
  d_items |> transmute(source = if_else(linksto == "outputevents", "outputevents", "chartevents"),
                       itemid, dict_label = label, dict_fluid = NA_character_)
)
feature_map <- feature_map |>
  left_join(dict, by = c("source", "itemid")) |>
  mutate(in_dictionary = !is.na(dict_label))
message("  -> Mapping rows: ", nrow(feature_map), "; found in dictionary: ", sum(feature_map$in_dictionary))
if (any(!feature_map$in_dictionary)) {
  message("  -> NOT in dictionary: ", paste(feature_map$itemid[!feature_map$in_dictionary], collapse = ", "))
}

# =============================================================================
# STEP 2. Cohort construction (Stage A)
# =============================================================================
message("Step 2: Building cohort ...")

# Harmonisation (protocol 12). Mappings are analyst assumptions.
map_race <- function(x) {
  dplyr::case_when(
    stringr::str_detect(x, "^WHITE|^PORTUGUESE") ~ "White",
    stringr::str_detect(x, "^BLACK") ~ "Black",
    stringr::str_detect(x, "HISPANIC|LATINO|SOUTH AMERICAN") ~ "Hispanic",
    stringr::str_detect(x, "^ASIAN") ~ "Asian",
    TRUE ~ "Other"
  )
}
map_insurance <- function(x) {
  dplyr::case_when(
    stringr::str_detect(x, regex("medicare", ignore_case = TRUE)) ~ "Medicare",
    stringr::str_detect(x, regex("medicaid", ignore_case = TRUE)) ~ "Medicaid",
    TRUE ~ "Other/Unknown"
  )
}
map_icu_type <- function(x) {
  dplyr::case_when(
    stringr::str_detect(x, "\\(TSICU\\)|Trauma") ~ "TSICU",
    stringr::str_detect(x, "Neuro") ~ "NICU",
    stringr::str_detect(x, "\\(CCU\\)|Coronary") ~ "CCU",
    stringr::str_detect(x, "\\(MICU\\)") & !stringr::str_detect(x, "SICU") ~ "MICU",
    stringr::str_detect(x, "\\(SICU\\)") & !stringr::str_detect(x, "MICU") ~ "SICU",
    TRUE ~ "Other"
  )
}

# Admission-level frame with rank within patient and age at admission
adm <- admissions |>
  dplyr::left_join(
    patients |> dplyr::select(subject_id, gender, anchor_age, anchor_year, anchor_year_group, dod),
    by = "subject_id"
  ) |>
  dplyr::arrange(subject_id, admittime, hadm_id) |>
  dplyr::group_by(subject_id) |>
  dplyr::mutate(adm_rank = dplyr::row_number()) |>
  dplyr::ungroup() |>
  dplyr::mutate(age_at_admit = anchor_age + (lubridate::year(admittime) - anchor_year))

# ICU-stay frame with rank within admission and within patient
stays <- icustays |>
  dplyr::arrange(subject_id, intime, stay_id) |>
  dplyr::group_by(hadm_id) |>
  dplyr::mutate(stay_rank_adm = dplyr::row_number()) |>
  dplyr::group_by(subject_id) |>
  dplyr::mutate(stay_rank_pat = dplyr::row_number()) |>
  dplyr::ungroup() |>
  dplyr::mutate(los_hours = as.numeric(difftime(outtime, intime, units = "hours"))) |>
  dplyr::left_join(
    adm |> dplyr::select(hadm_id, adm_rank, admittime, dischtime, deathtime, hospital_expire_flag,
                         discharge_location, race, insurance, gender, anchor_age, anchor_year,
                         anchor_year_group, dod, age_at_admit),
    by = "hadm_id"
  ) |>
  dplyr::mutate(age_at_icu = anchor_age + (lubridate::year(intime) - anchor_year))

# All criteria in ONE mutate (r-coding standard): inspect each flag individually
stays <- stays |>
  dplyr::mutate(
    f_age       = !is.na(age_at_icu) & age_at_icu >= min_age_years,
    f_first_adm = !is.na(adm_rank) & adm_rank == 1,
    f_first_stay = stay_rank_adm == 1,
    f_los       = !is.na(los_hours) & los_hours >= min_los_hours,
    f_outcome   = !is.na(hospital_expire_flag),
    f_protocol  = f_age & f_first_adm & f_first_stay & f_los & f_outcome
  )

# Attrition in protocol order (Stage A). Unit shown: patients / admissions / ICU stays.
n_row <- function(step, criterion, a, s) {
  tibble::tibble(
    step = step, criterion = criterion,
    n_patients = dplyr::n_distinct(a$subject_id),
    n_admissions = nrow(a),
    n_icu_stays = nrow(s)
  )
}
a0 <- adm; s0 <- stays
a1 <- a0 |> dplyr::filter(age_at_admit >= min_age_years); s1 <- s0 |> dplyr::semi_join(a1, by = "hadm_id")
a2 <- a1 |> dplyr::filter(adm_rank == 1);                s2 <- s1 |> dplyr::semi_join(a2, by = "hadm_id")
s3 <- s2 |> dplyr::filter(f_first_stay);                 a3 <- a2 |> dplyr::semi_join(s3, by = "hadm_id")
s4 <- s3 |> dplyr::filter(f_los);                        a4 <- a3 |> dplyr::semi_join(s4, by = "hadm_id")
s5 <- s4 |> dplyr::filter(f_outcome);                    a5 <- a4 |> dplyr::semi_join(s5, by = "hadm_id")

attrition <- dplyr::bind_rows(
  n_row(0, "All TinyEHR patients (admissions / ICU stays as available)", a0, s0),
  n_row(1, "Age >= 18 years", a1, s1),
  n_row(2, "First hospital admission of the patient", a2, s2),
  n_row(3, "First ICU stay in that admission (admission must have an ICU stay)", a3, s3),
  n_row(4, "ICU length of stay >= 4 hours", a4, s4),
  n_row(5, "In-hospital mortality outcome available", a5, s5)
) |>
  dplyr::mutate(
    pct_patients_remaining = round(100 * n_patients / n_patients[1], 1),
    n_patients_lost = dplyr::lag(n_patients, default = dplyr::first(n_patients)) - n_patients
  )
message("  -> Attrition (patients): ", paste(attrition$n_patients, collapse = " -> "))

cohort <- stays |>
  dplyr::filter(f_protocol) |>
  dplyr::mutate(
    sex = gender,
    race_group = map_race(race),
    insurance_group = map_insurance(insurance),
    icu_type = map_icu_type(first_careunit),
    age_stratum = cut(age_at_icu, c(18, 45, 65, 75, Inf), right = FALSE,
                      labels = c("18-44", "45-64", "65-74", ">=75")),
    died = hospital_expire_flag,
    window_end = intime + lubridate::hours(window_hours),
    window_hours_available = pmin(window_hours, los_hours)
  )
message("  -> Final analytical cohort: ", nrow(cohort), " ICU stays / ",
        dplyr::n_distinct(cohort$subject_id), " patients; deaths: ", sum(cohort$died))

# Tiered definitions (Tate): sensitivity of the headline cohort to protocol rules
tiers <- dplyr::bind_rows(
  stays |>
    dplyr::filter(f_age, f_first_adm, f_first_stay, f_los, f_outcome) |>
    dplyr::summarise(tier = "1 Strict protocol (first admission, first ICU stay)",
                     n_stays = dplyr::n(), n_patients = dplyr::n_distinct(subject_id), n_deaths = sum(hospital_expire_flag)),
  stays |>
    dplyr::filter(f_age, f_los, f_outcome, stay_rank_pat == 1) |>
    dplyr::summarise(tier = "2 First ICU stay of the patient, any admission",
                     n_stays = dplyr::n(), n_patients = dplyr::n_distinct(subject_id), n_deaths = sum(hospital_expire_flag)),
  stays |>
    dplyr::filter(f_age, f_los, f_outcome, f_first_stay) |>
    dplyr::summarise(tier = "3 First ICU stay of every admission",
                     n_stays = dplyr::n(), n_patients = dplyr::n_distinct(subject_id), n_deaths = sum(hospital_expire_flag)),
  stays |>
    dplyr::filter(f_age, f_los, f_outcome) |>
    dplyr::summarise(tier = "4 All ICU stays (no uniqueness rule)",
                     n_stays = dplyr::n(), n_patients = dplyr::n_distinct(subject_id), n_deaths = sum(hospital_expire_flag))
) |>
  dplyr::mutate(mortality_pct = round(100 * n_deaths / n_stays, 1))

# =============================================================================
# STEP 3. First-24h observations (Stage B)
# =============================================================================
message("Step 3: Extracting observations from chartevents / outputevents / labevents ...")
cohort_keys <- cohort |>
  dplyr::select(subject_id, hadm_id, stay_id, intime, window_end, los_hours, admittime, dischtime)
map_chart <- feature_map |> dplyr::filter(source == "chartevents")
map_out   <- feature_map |> dplyr::filter(source == "outputevents")
map_lab   <- feature_map |> dplyr::filter(source == "labevents")

# chartevents: whole-table read of needed columns, then item filter
chart_all <- readr::read_csv(
  file.path(root_raw, "icu/chartevents.csv"), show_col_types = FALSE, progress = FALSE,
  col_types = readr::cols_only(
    subject_id = "i", hadm_id = "i", stay_id = "i", charttime = "T", storetime = "T",
    itemid = "i", value = "c", valuenum = "d", valueuom = "c"
  )
) |>
  dplyr::filter(itemid %in% map_chart$itemid)
message("  -> chartevents rows for mapped items: ", nrow(chart_all))

out_all <- readr::read_csv(
  file.path(root_raw, "icu/outputevents.csv"), show_col_types = FALSE, progress = FALSE,
  col_types = readr::cols_only(
    subject_id = "i", hadm_id = "i", stay_id = "i", charttime = "T", storetime = "T",
    itemid = "i", value = "d", valueuom = "c"
  )
) |>
  dplyr::mutate(valuenum = value)
out_urine <- out_all |> dplyr::filter(itemid %in% map_out$itemid)
message("  -> outputevents rows: ", nrow(out_all), "; urine items: ", nrow(out_urine))

lab_all <- readr::read_csv(
  file.path(root_raw, "hosp/labevents.csv"), show_col_types = FALSE, progress = FALSE,
  col_types = readr::cols_only(
    labevent_id = "i", subject_id = "i", hadm_id = "i", specimen_id = "i", itemid = "i",
    charttime = "T", storetime = "T", value = "c", valuenum = "d", valueuom = "c"
  )
) |>
  dplyr::filter(itemid %in% map_lab$itemid)
message("  -> labevents rows for mapped items: ", nrow(lab_all))

# Event-level audit before restricting to the window (stay-keyed tables)
audit_stay_events <- function(ev, src) {
  ev |>
    dplyr::left_join(icustays |> dplyr::select(stay_id, st_hadm = hadm_id, st_subject = subject_id,
                                               st_intime = intime, st_outtime = outtime),
                     by = "stay_id") |>
    dplyr::left_join(cohort_keys |> dplyr::select(stay_id, coh_intime = intime, coh_end = window_end),
                     by = "stay_id") |>
    dplyr::group_by(itemid) |>
    dplyr::summarise(
      source = src,
      n_total = dplyr::n(),
      n_stay_missing = sum(is.na(stay_id)),
      n_stay_unknown = sum(!is.na(stay_id) & is.na(st_hadm)),
      n_hadm_mismatch = sum(!is.na(st_hadm) & hadm_id != st_hadm, na.rm = TRUE),
      n_subject_mismatch = sum(!is.na(st_subject) & subject_id != st_subject, na.rm = TRUE),
      n_before_stay = sum(!is.na(st_intime) & charttime < st_intime),
      n_after_stay = sum(!is.na(st_outtime) & charttime > st_outtime),
      n_storetime_before_charttime = sum(!is.na(storetime) & storetime < charttime),
      n_cohort = sum(!is.na(coh_intime)),
      n_cohort_pre_window = sum(!is.na(coh_intime) & charttime < coh_intime),
      n_cohort_in_window = sum(!is.na(coh_intime) & charttime >= coh_intime & charttime <= coh_end),
      n_cohort_post_window = sum(!is.na(coh_intime) & charttime > coh_end),
      n_dup_exact = sum(duplicated(paste(stay_id, charttime, valuenum, value))),
      .groups = "drop"
    )
}
audit_chart <- audit_stay_events(chart_all, "chartevents")
audit_out   <- audit_stay_events(out_urine |> dplyr::mutate(value = as.character(value)), "outputevents")

# Lab audit: labs are keyed by subject_id (hadm_id may be NULL by design, limitation L11)
lab_c <- lab_all |>
  dplyr::inner_join(cohort_keys |> dplyr::select(subject_id, stay_id, idx_hadm = hadm_id,
                                                  intime, window_end, admittime, dischtime),
                    by = "subject_id", relationship = "many-to-many") |>
  dplyr::mutate(source = "labevents",
                in_adm = charttime >= admittime & charttime <= dischtime,
                rel_h = as.numeric(difftime(charttime, intime, units = "hours")))
audit_lab <- lab_c |>
  dplyr::group_by(itemid) |>
  dplyr::summarise(
    source = "labevents",
    n_total = dplyr::n(),
    n_hadm_missing = sum(is.na(hadm_id)),
    n_hadm_other = sum(!is.na(hadm_id) & hadm_id != idx_hadm),
    n_storetime_before_charttime = sum(!is.na(storetime) & storetime < charttime),
    n_cohort = sum(in_adm),
    n_cohort_pre_window = sum(in_adm & rel_h < 0),
    n_cohort_in_window = sum(in_adm & rel_h >= 0 & rel_h <= window_hours),
    n_cohort_post_window = sum(in_adm & rel_h > window_hours),
    n_in_window_hadm_missing = sum(rel_h >= 0 & rel_h <= window_hours & is.na(hadm_id)),
    n_in_window_hadm_other = sum(rel_h >= 0 & rel_h <= window_hours & !is.na(hadm_id) & hadm_id != idx_hadm),
    n_dup_exact = sum(duplicated(paste(stay_id, specimen_id, charttime, valuenum, value))),
    .groups = "drop"
  )
event_audit <- dplyr::bind_rows(audit_chart, audit_out, audit_lab) |>
  dplyr::left_join(feature_map |> dplyr::distinct(source, itemid, concept, dict_label), by = c("source", "itemid"))

# ---- Long observation table inside the window ----
standardise <- function(ev, src) {
  ev |>
    dplyr::inner_join(cohort_keys |> dplyr::select(stay_id, subject_id_c = subject_id, intime, window_end),
                      by = "stay_id") |>
    dplyr::transmute(stay_id, itemid, source = src, charttime, valuenum, valueuom, intime, window_end)
}
obs_chart <- standardise(chart_all, "chartevents")
obs_out   <- standardise(out_urine, "outputevents")
obs_lab <- lab_c |>
  dplyr::transmute(stay_id, itemid, source = "labevents", charttime, valuenum, valueuom, intime, window_end)

obs <- dplyr::bind_rows(obs_chart, obs_out, obs_lab) |>
  dplyr::mutate(rel_h = as.numeric(difftime(charttime, intime, units = "hours"))) |>
  dplyr::filter(rel_h >= 0, rel_h <= window_hours) |>
  dplyr::left_join(feature_map |> dplyr::select(source, itemid, concept, group, unit_regex, lo, hi),
                   by = c("source", "itemid"))

# GCS: total = eye + verbal + motor charted at the same time
gcs_comp <- obs |>
  dplyr::filter(concept == "gcs_total") |>
  dplyr::group_by(stay_id, charttime) |>
  dplyr::summarise(n_components = dplyr::n_distinct(itemid), total = sum(valuenum),
                   rel_h = dplyr::first(rel_h), intime = dplyr::first(intime),
                   window_end = dplyr::first(window_end), .groups = "drop")
gcs_triplets <- gcs_comp |>
  dplyr::summarise(n_charttimes = dplyr::n(), n_complete = sum(n_components == 3),
                   n_incomplete = sum(n_components < 3))
message("  -> GCS charttimes: ", gcs_triplets$n_charttimes, " (complete triplets: ", gcs_triplets$n_complete, ")")
gcs_obs <- gcs_comp |>
  dplyr::filter(n_components == 3) |>
  dplyr::transmute(stay_id, itemid = NA_integer_, source = "chartevents", charttime,
                   valuenum = total, valueuom = NA_character_, intime, window_end, rel_h,
                   concept = "gcs_total", group = "Vital", unit_regex = NA_character_, lo = 3, hi = 15,
                   gcs_component_row = FALSE)

obs <- obs |>
  dplyr::filter(concept != "gcs_total") |>
  dplyr::mutate(gcs_component_row = FALSE) |>
  dplyr::bind_rows(gcs_obs)

# Unit validation -> harmonisation -> plausibility (protocol section 11 order)
obs <- obs |>
  dplyr::mutate(
    unit_blank = is.na(valueuom) | valueuom == "",
    unit_ok = dplyr::case_when(
      is.na(unit_regex) ~ unit_blank,
      TRUE ~ !unit_blank & stringr::str_detect(valueuom, stringr::regex(unit_regex, ignore_case = TRUE))
    ),
    value_std = dplyr::if_else(concept == "temperature" & itemid == 223761, (valuenum - 32) * 5 / 9, valuenum),
    value_missing = is.na(value_std),
    unit_ok = dplyr::if_else(concept == "gcs_total", TRUE, unit_ok),
    plausible = !is.na(value_std) & value_std >= lo & value_std <= hi
  )
message("  -> Observations in window: ", nrow(obs), "; unit mismatch: ", sum(!obs$unit_ok),
        "; implausible (unit ok): ", sum(obs$unit_ok & !obs$plausible))

# ---- Aggregation per stay x concept ----
agg <- obs |>
  dplyr::group_by(stay_id, concept) |>
  dplyr::summarise(
    n_raw = dplyr::n(),
    n_unit_bad = sum(!unit_ok),
    n_value_missing = sum(unit_ok & value_missing),
    n_implausible = sum(unit_ok & !value_missing & !plausible),
    n_valid = sum(unit_ok & plausible),
    n_itemids = dplyr::n_distinct(itemid[unit_ok & plausible]),
    raw_min = safe_stat(value_std[unit_ok & !value_missing], min),
    raw_max = safe_stat(value_std[unit_ok & !value_missing], max),
    min = safe_stat(value_std[unit_ok & plausible], min),
    max = safe_stat(value_std[unit_ok & plausible], max),
    mean = safe_stat(value_std[unit_ok & plausible], mean),
    total = if (concept[1] == "urine_output") sum(value_std[unit_ok & plausible]) else NA_real_,
    n_hours_with_record = if (concept[1] == "urine_output") {
      dplyr::n_distinct(floor(rel_h[unit_ok & plausible]))
    } else NA_integer_,
    first_obs_h = safe_stat(rel_h[unit_ok & plausible], base::min),
    last_obs_h = safe_stat(rel_h[unit_ok & plausible], base::max),
    .groups = "drop"
  )

# Pre-ICU look-back sensitivity for labs (same admission, not in protocol)
lab_pre <- lab_c |>
  dplyr::inner_join(feature_map |> dplyr::select(source, itemid, concept, lo, hi, unit_regex),
                    by = c("source" = "source", "itemid" = "itemid")) |>
  dplyr::filter(rel_h < 0, rel_h >= -lookback_hours, !is.na(valuenum), valuenum >= lo, valuenum <= hi) |>
  dplyr::distinct(stay_id, concept)

# Complete grid: every cohort stay x every concept (absent = 0 observations)
features_long <- tidyr::expand_grid(stay_id = cohort$stay_id, concept = concept_levels) |>
  dplyr::left_join(agg, by = c("stay_id", "concept")) |>
  dplyr::mutate(
    dplyr::across(c(n_raw, n_unit_bad, n_value_missing, n_implausible, n_valid), ~ tidyr::replace_na(.x, 0L))
  ) |>
  dplyr::left_join(lab_pre |> dplyr::mutate(has_prewindow = TRUE), by = c("stay_id", "concept")) |>
  dplyr::mutate(has_prewindow = tidyr::replace_na(has_prewindow, FALSE))

# =============================================================================
# STEP 4. Elixhauser comorbidity count (composite predictor 10.2)
# =============================================================================
message("Step 4: Elixhauser count from diagnoses_icd ...")
dx <- read_raw("hosp/diagnoses_icd.csv") |>
  dplyr::semi_join(cohort, by = "hadm_id")
d_icd <- read_raw("hosp/d_icd_diagnoses.csv")
dx_check <- dx |>
  dplyr::left_join(d_icd |> dplyr::mutate(in_dict = TRUE) |> dplyr::select(icd_code, icd_version, in_dict),
                   by = c("icd_code", "icd_version")) |>
  dplyr::mutate(in_dict = tidyr::replace_na(in_dict, FALSE))
message("  -> Index-admission diagnoses: ", nrow(dx), "; matched to dictionary: ", sum(dx_check$in_dict))

elix_one <- function(df, version) {
  df <- df |>
    dplyr::filter(icd_version == version) |>
    dplyr::mutate(code_nodot = stringr::str_remove_all(icd_code, "\\."))
  if (nrow(df) == 0) return(NULL)
  map_name <- if (version == 10) "elixhauser_icd10_quan" else "elixhauser_icd9_quan"
  comorbidity::comorbidity(df, id = "hadm_id", code = "code_nodot", map = map_name, assign0 = FALSE) |>
    tibble::as_tibble()
}
elix_cat <- dplyr::bind_rows(elix_one(dx, 9), elix_one(dx, 10))
elix_flags <- elix_cat |>
  dplyr::select(-dplyr::any_of(c("score", "index", "wscore", "windex"))) |>
  dplyr::group_by(hadm_id) |>
  dplyr::summarise(dplyr::across(dplyr::everything(), ~ as.integer(any(.x > 0))), .groups = "drop")
elix <- elix_flags |>
  dplyr::mutate(elixhauser_n = rowSums(dplyr::pick(-hadm_id)))
elix_summary <- tibble::tibble(
  n_categories_implemented = ncol(elix_flags) - 1,
  n_adm_with_dx = dplyr::n_distinct(dx$hadm_id),
  n_dx_rows = nrow(dx),
  n_dx_in_dict = sum(dx_check$in_dict),
  n_icd9 = sum(dx$icd_version == 9),
  n_icd10 = sum(dx$icd_version == 10),
  n_with_decimal = sum(stringr::str_detect(dx$icd_code, "\\."))
)
message("  -> Elixhauser categories: ", elix_summary$n_categories_implemented,
        "; admissions with diagnoses: ", elix_summary$n_adm_with_dx)

elix_long <- cohort |>
  dplyr::select(stay_id, hadm_id) |>
  dplyr::left_join(elix |> dplyr::select(hadm_id, elixhauser_n), by = "hadm_id") |>
  dplyr::left_join(dx |> dplyr::count(hadm_id, name = "n_dx"), by = "hadm_id") |>
  dplyr::transmute(
    stay_id, concept = "elixhauser_count",
    n_raw = tidyr::replace_na(n_dx, 0L), n_unit_bad = 0L, n_value_missing = 0L, n_implausible = 0L,
    n_valid = dplyr::if_else(is.na(elixhauser_n), 0L, 1L),
    min = elixhauser_n, max = elixhauser_n, mean = elixhauser_n,
    raw_min = elixhauser_n, raw_max = elixhauser_n
  )
features_long <- features_long |>
  dplyr::filter(concept != "elixhauser_count") |>
  dplyr::bind_rows(elix_long |> dplyr::mutate(has_prewindow = FALSE))

# =============================================================================
# STEP 5. Save
# =============================================================================
message("Step 5: Saving artifacts ...")
fst::write_fst(cohort |> dplyr::select(-dplyr::any_of(c("intime_chr"))), file.path(dir_cohort, "cohort.fst"))
saveRDS(list(attrition = attrition, tiers = tiers, stays_flags = stays |>
               dplyr::summarise(dplyr::across(c(f_age, f_first_adm, f_first_stay, f_los, f_outcome, f_protocol), sum),
                                n = dplyr::n())),
        file.path(dir_cohort, "attrition.rds"))
fst::write_fst(features_long, file.path(dir_features, "features_long.fst"))
fst::write_fst(obs |> dplyr::select(stay_id, concept, itemid, source, rel_h, value_std, valueuom, unit_ok, plausible),
               file.path(dir_features, "obs_window.fst"))
saveRDS(list(event_audit = event_audit, gcs = gcs_triplets, elix_summary = elix_summary,
             dx_check = dx_check |> dplyr::count(icd_version, in_dict)),
        file.path(dir_features, "event_audit.rds"))
saveRDS(feature_map, file.path(dir_features, "feature_map.rds"))
message("Done. Cohort ", nrow(cohort), " stays; features_long ", nrow(features_long), " rows.")
