# =============================================================================
# 00_Get_the_Data.R
#
# Acquire the TinyEHR dataset (MIMIC-IV format) and all related documentation.
#
# TinyEHR is a 100-patient, openly licensed (ODbL-1.0) EHR dataset derived from
# the MIMIC-IV Clinical Database Demo v2.2. It needs no credentialing.
#   Repo:  https://github.com/vidulpanickan/TinyEHR
#
# What this script downloads
#   1. Data (MIMIC-IV format: 22 hosp, 9 icu, 1 notes table)
#                                           -> data/raw/tinyehr_mimic_format/
#      plus the per-patient date-shift file  -> data/raw/metadata/date_offsets.csv
#      (TinyEHR counts these 33 files as "33 tables")
#   2. TinyEHR documentation                -> data/documentation/tinyehr/
#      (README, ABOUT_THE_DATA, LICENSE)
#   3. PhysioNet MIMIC-IV Demo v2.2 docs    -> data/documentation/physionet_mimic_iv_demo_v2.2/
#      (README, LICENSE, SHA256SUMS, demo_subject_id) - the upstream source
#   4. Official MIMIC-IV table docs          -> data/documentation/mimic_iv_official_docs/
#      (markdown behind https://mimic.mit.edu/docs/iv/, from MIT-LCP/mimic-website)
#   5. MIMIC-IV paper (Sci Data 2023, CC-BY) -> data/documentation/mimic_iv_paper/
#
# After downloading it verifies row counts against the counts published in
# ABOUT_THE_DATA.md and writes a manifest (bytes, md5, rows, source URL).
#
# Dependencies: base R only. data.table is used for faster row counting if it
# is installed, otherwise utils::read.csv is used.
#
# Usage: source("code/00_Get_the_Data.R") from the project root, or
#        Rscript code/00_Get_the_Data.R
# =============================================================================

# ---- 0. Settings -------------------------------------------------------------

FORCE_REDOWNLOAD <- FALSE   # TRUE re-downloads files that already exist
GET_OMOP_FORMAT  <- FALSE   # TRUE also pulls the OMOP CDM copy of the same data

TINYEHR_REPO    <- "vidulpanickan/TinyEHR"
TINYEHR_REF     <- "main"
MIMIC_DOCS_REPO <- "MIT-LCP/mimic-website"
MIMIC_DOCS_REF  <- "main"
PHYSIONET_DEMO  <- "https://physionet.org/files/mimic-iv-demo/2.2"

options(timeout = max(600, getOption("timeout")))  # chartevents.csv is ~65 MB

# ---- 1. Locate the project root ---------------------------------------------

find_project_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) return(here::here())
  # Rscript: path of this file is in --file=
  arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(arg)) {
    return(normalizePath(file.path(dirname(sub("^--file=", "", arg)), "..")))
  }
  # RStudio: path of the open script
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    p <- rstudioapi::getSourceEditorContext()$path
    if (nzchar(p)) return(normalizePath(file.path(dirname(p), "..")))
  }
  getwd()
}

ROOT     <- find_project_root()
DATA_DIR <- file.path(ROOT, "data")
RAW_DIR  <- file.path(DATA_DIR, "raw")
DOC_DIR  <- file.path(DATA_DIR, "documentation")
message("Project root: ", ROOT)

# ---- 2. Helpers --------------------------------------------------------------

raw_gh <- function(repo, ref, path) {
  sprintf("https://raw.githubusercontent.com/%s/%s/%s", repo, ref, path)
}

rel_to_data <- function(path) {
  # Path relative to DATA_DIR, with forward slashes, for the manifest
  full <- gsub("\\\\", "/", normalizePath(path, mustWork = FALSE))
  base <- gsub("\\\\", "/", normalizePath(DATA_DIR, mustWork = FALSE))
  sub(paste0("^", base, "/?"), "", full)
}

# Download one file if missing (or if FORCE_REDOWNLOAD). Returns a 1-row
# data.frame describing the outcome.
fetch_file <- function(url, dest, group) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  status <- "exists"
  if (FORCE_REDOWNLOAD || !file.exists(dest)) {
    message(sprintf("  [%s] %s", group, basename(dest)))
    tmp <- paste0(dest, ".part")
    rc <- tryCatch(
      download.file(url, tmp, mode = "wb", quiet = TRUE, method = "libcurl"),
      error   = function(e) { message("    ERROR: ", conditionMessage(e)); 1L },
      warning = function(w) { message("    WARNING: ", conditionMessage(w)); 1L }
    )
    if (identical(rc, 0L) && file.exists(tmp) && file.size(tmp) > 0) {
      file.rename(tmp, dest)
      status <- "downloaded"
    } else {
      if (file.exists(tmp)) unlink(tmp)
      status <- "FAILED"
    }
  }
  data.frame(
    group  = group,
    file   = rel_to_data(dest),
    url    = url,
    status = status,
    bytes  = if (file.exists(dest)) file.size(dest) else NA_real_,
    md5    = if (file.exists(dest)) unname(tools::md5sum(dest)) else NA_character_,
    stringsAsFactors = FALSE
  )
}

# Count data rows in a CSV, honouring quoted fields that contain newlines
# (noteevents.csv has multi-line note text, so a plain line count is wrong).
count_csv_rows <- function(path) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    return(nrow(data.table::fread(path, select = 1L, showProgress = FALSE,
                                  colClasses = "character")))
  }
  nrow(utils::read.csv(path, colClasses = "character", check.names = FALSE))
}

# Record the git commit the data was taken from, for reproducibility.
github_head_sha <- function(repo, ref) {
  url <- sprintf("https://api.github.com/repos/%s/commits/%s", repo, ref)
  txt <- tryCatch(paste(readLines(url, warn = FALSE), collapse = ""),
                  error = function(e) NA_character_)
  if (is.na(txt)) return(NA_character_)
  m <- regmatches(txt, regexpr('"sha":\\s*"[0-9a-f]{40}"', txt))
  if (!length(m)) return(NA_character_)
  sub('"sha":\\s*"([0-9a-f]{40})"', "\\1", m[1])
}

# ---- 3. Define what to download ---------------------------------------------

# 3a. TinyEHR MIMIC-format tables, with the row counts published in
#     ABOUT_THE_DATA.md (used for verification below).
mimic_tables <- data.frame(
  module = c(rep("hosp", 22), rep("icu", 9), "notes"),
  table  = c(
    # hosp
    "patients", "admissions", "transfers", "services", "diagnoses_icd",
    "procedures_icd", "drgcodes", "hcpcsevents", "labevents",
    "microbiologyevents", "prescriptions", "pharmacy", "emar", "emar_detail",
    "poe", "poe_detail", "omr", "provider", "d_labitems", "d_icd_diagnoses",
    "d_icd_procedures", "d_hcpcs",
    # icu
    "icustays", "chartevents", "datetimeevents", "inputevents", "outputevents",
    "procedureevents", "ingredientevents", "d_items", "caregiver",
    # notes
    "noteevents"),
  expected_rows = c(
    100, 275, 1190, 319, 4506, 722, 454, 61, 107727, 2899, 18087, 15306,
    35835, 72018, 45154, 3795, 2964, 40508, 1622, 109775, 85257, 89200,
    140, 668862, 15280, 20404, 9362, 1468, 25728, 4014, 15468,
    4580),
  stringsAsFactors = FALSE
)
mimic_tables$rel_path <- sprintf("tinyehr_mimic_format/%s/%s.csv",
                                 mimic_tables$module, mimic_tables$table)

# 3b. OMOP-format tables (optional; same 100 patients in OMOP CDM v5.3.1)
omop_tables <- c(
  "2b_concept", "2b_concept_relationship", "2b_vocabulary",
  "attribute_definition", "care_site", "cdm_source", "cohort",
  "cohort_attribute", "cohort_definition", "condition_era",
  "condition_occurrence", "cost", "death", "device_exposure", "dose_era",
  "drug_era", "drug_exposure", "fact_relationship", "location", "measurement",
  "metadata", "note", "note_nlp", "observation", "observation_period",
  "payer_plan_period", "person", "procedure_occurrence", "provider",
  "specimen", "visit_detail", "visit_occurrence")

# 3c. Official MIMIC-IV documentation pages (markdown source of mimic.mit.edu).
#     hosp and icu modules cover every table in TinyEHR; the note module is
#     included because TinyEHR adds a notes table modelled on MIMIC-IV-Note.
mimic_doc_pages <- c(
  "docs/iv/index.md",
  "docs/iv/about/index.md", "docs/iv/about/schema-overview.md",
  "docs/iv/about/concepts.md", "docs/iv/about/changelog.md",
  "docs/iv/about/whatsnew.md",
  "docs/about/glossary.md",
  "docs/iv/modules/index.md",
  "docs/iv/modules/hosp/index.md",
  sprintf("docs/iv/modules/hosp/%s.md",
          mimic_tables$table[mimic_tables$module == "hosp"]),
  "docs/iv/modules/icu/index.md",
  # the website spells this one page "datetimesevents.md"
  sprintf("docs/iv/modules/icu/%s.md",
          sub("^datetimeevents$", "datetimesevents",
              mimic_tables$table[mimic_tables$module == "icu"])),
  "docs/iv/modules/note/index.md", "docs/iv/modules/note/discharge.md",
  "docs/iv/modules/note/discharge_detail.md",
  "docs/iv/modules/note/radiology.md", "docs/iv/modules/note/radiology_detail.md",
  # shared snippets the pages include (what subject_id, hadm_id, stay_id mean)
  "_includes/subject_id.md", "_includes/hadm_id.md", "_includes/stay_id.md",
  "_includes/provider_id.md", "_includes/caregiver_id.md")

# ---- 4. Download -------------------------------------------------------------

manifest <- list()

message("\n== 1. TinyEHR data (MIMIC-IV format) ==")
for (i in seq_len(nrow(mimic_tables))) {
  manifest[[length(manifest) + 1]] <- fetch_file(
    url   = raw_gh(TINYEHR_REPO, TINYEHR_REF, mimic_tables$rel_path[i]),
    dest  = file.path(RAW_DIR, mimic_tables$rel_path[i]),
    group = "data_mimic")
}
manifest[[length(manifest) + 1]] <- fetch_file(
  url   = raw_gh(TINYEHR_REPO, TINYEHR_REF, "metadata/date_offsets.csv"),
  dest  = file.path(RAW_DIR, "metadata", "date_offsets.csv"),
  group = "data_metadata")

if (GET_OMOP_FORMAT) {
  message("\n== 1b. TinyEHR data (OMOP CDM format) ==")
  for (tb in omop_tables) {
    rel <- sprintf("tinyehr_omop_format/%s.csv", tb)
    manifest[[length(manifest) + 1]] <- fetch_file(
      url   = raw_gh(TINYEHR_REPO, TINYEHR_REF, rel),
      dest  = file.path(RAW_DIR, rel),
      group = "data_omop")
  }
}

message("\n== 2. TinyEHR documentation ==")
for (f in c("README.md", "ABOUT_THE_DATA.md", "LICENSE")) {
  manifest[[length(manifest) + 1]] <- fetch_file(
    url   = raw_gh(TINYEHR_REPO, TINYEHR_REF, f),
    dest  = file.path(DOC_DIR, "tinyehr", f),
    group = "doc_tinyehr")
}

message("\n== 3. PhysioNet MIMIC-IV Demo v2.2 documentation (upstream source) ==")
for (f in c("README.txt", "LICENSE.txt", "SHA256SUMS.txt", "demo_subject_id.csv")) {
  manifest[[length(manifest) + 1]] <- fetch_file(
    url   = sprintf("%s/%s", PHYSIONET_DEMO, f),
    dest  = file.path(DOC_DIR, "physionet_mimic_iv_demo_v2.2", f),
    group = "doc_physionet")
}

message("\n== 4. Official MIMIC-IV table documentation (mimic.mit.edu source) ==")
for (p in mimic_doc_pages) {
  manifest[[length(manifest) + 1]] <- fetch_file(
    url   = raw_gh(MIMIC_DOCS_REPO, MIMIC_DOCS_REF, p),
    dest  = file.path(DOC_DIR, "mimic_iv_official_docs", sub("^docs/", "", p)),
    group = "doc_mimic_official")
}

message("\n== 5. MIMIC-IV paper (Johnson et al. 2023, Sci Data, CC-BY) ==")
manifest[[length(manifest) + 1]] <- fetch_file(
  url   = "https://www.nature.com/articles/s41597-022-01899-x.pdf",
  dest  = file.path(DOC_DIR, "mimic_iv_paper",
                    "Johnson_2023_MIMIC-IV_Scientific_Data.pdf"),
  group = "doc_paper")

manifest <- do.call(rbind, manifest)

# ---- 5. Verify row counts against published counts ---------------------------

message("\n== 6. Verifying row counts against ABOUT_THE_DATA.md ==")
mimic_tables$observed_rows <- NA_integer_
for (i in seq_len(nrow(mimic_tables))) {
  p <- file.path(RAW_DIR, mimic_tables$rel_path[i])
  if (file.exists(p)) mimic_tables$observed_rows[i] <- count_csv_rows(p)
}
mimic_tables$rows_match <- mimic_tables$observed_rows == mimic_tables$expected_rows

print(mimic_tables[, c("module", "table", "expected_rows", "observed_rows", "rows_match")],
      row.names = FALSE)

# Attach row counts to the manifest
idx <- match(file.path("raw", mimic_tables$rel_path), manifest$file)
manifest$rows <- NA_integer_
manifest$rows[idx] <- mimic_tables$observed_rows
manifest$expected_rows <- NA_integer_
manifest$expected_rows[idx] <- mimic_tables$expected_rows

# ---- 6. Write manifest and provenance ----------------------------------------

manifest$retrieved_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
tinyehr_sha <- github_head_sha(TINYEHR_REPO, TINYEHR_REF)
docs_sha    <- github_head_sha(MIMIC_DOCS_REPO, MIMIC_DOCS_REF)
manifest$source_commit <- NA_character_
manifest$source_commit[grepl("^data_|^doc_tinyehr", manifest$group)] <- tinyehr_sha
manifest$source_commit[manifest$group == "doc_mimic_official"]        <- docs_sha

manifest_path <- file.path(DATA_DIR, "manifest_00_get_the_data.csv")
write.csv(manifest, manifest_path, row.names = FALSE)

# ---- 7. Summary --------------------------------------------------------------

n_failed   <- sum(manifest$status == "FAILED")
n_mismatch <- sum(!mimic_tables$rows_match, na.rm = TRUE)
n_missing  <- sum(is.na(mimic_tables$observed_rows))

message("\n== Summary ==")
message(sprintf("Files downloaded : %d", sum(manifest$status == "downloaded")))
message(sprintf("Files already had: %d", sum(manifest$status == "exists")))
message(sprintf("Files FAILED     : %d", n_failed))
message(sprintf("Total size       : %.1f MB", sum(manifest$bytes, na.rm = TRUE) / 1e6))
message(sprintf("Tables checked   : %d  (row-count mismatches: %d, missing: %d)",
                nrow(mimic_tables), n_mismatch, n_missing))
message(sprintf("TinyEHR commit   : %s", tinyehr_sha))
message(sprintf("Manifest         : %s", manifest_path))

if (n_failed > 0) {
  message("\nFailed downloads:")
  print(manifest[manifest$status == "FAILED", c("group", "file", "url")],
        row.names = FALSE)
}
if (n_mismatch > 0 || n_missing > 0) {
  warning("Row counts do not all match ABOUT_THE_DATA.md. ",
          "Check whether the upstream repo has been updated since v0.2.0.")
}
