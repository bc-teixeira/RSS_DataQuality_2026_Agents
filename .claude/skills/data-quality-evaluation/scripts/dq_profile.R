#!/usr/bin/env Rscript
# dq_profile.R - mechanical data quality profiling in the spirit of Redman, Hoerl and Tate.
# R port of dq_profile.py: same checks, same outputs, same rules.json.
#
# Computes, for a tabular file:
#   * initial data analysis: shape, types, empty/constant/high-cardinality columns, placeholder values,
#     numeric and categorical summaries
#   * completeness, validity (rules), uniqueness, cross-field consistency per critical data element (CDE)
#   * the record-level perfect-record score (Redman's Friday Afternoon Measurement arithmetic) with a Wilson CI
#   * an error Pareto
#   * defect rate by period with p-chart limits and by group with funnel limits
#   * date spikes (batch / retrospective entry)
#   * a FAM worksheet of the most recent N records for a human pass
#
# Usage:
#   Rscript dq_profile.R data.csv --critical a,b,c [--rules rules.json] [--key id1,id2]
#           [--date-col d] [--period M|Q|Y] [--group-col g] [--fam-sample 100] [--out dq_output]
#           [--nrows N] [--no-plots]
#
# Outputs in --out: dq_profile.json, dq_summary.md, fam_worksheet.csv, and PNG charts unless --no-plots.
# Requires: R >= 4.0 and the jsonlite package. Optional: data.table (fast CSV), readxl (.xlsx), arrow (.parquet).
#
# Differences from the Python version:
#   * _record_index in the FAM worksheet is 1-based (R row numbers); Python's is 0-based.
#   * Cross-field expressions may be written in pandas style (translated automatically, see translate_expr)
#     or in native R by using the "r_expr" key instead of "expr".
#   * Everything is read as text first; columns are parsed to numbers or dates only when a rule says so or the
#     column looks numeric/date-like, so mixed columns stay text rather than silently losing values.

suppressPackageStartupMessages(library(jsonlite))

DEFAULT_PLACEHOLDERS <- c("", "NA", "N/A", "NULL", "null", "None", "none", "-", "?", "UNKNOWN", "Unknown",
                          "unknown", "9999", "-999", "999", "-1", "NaN", "nan", ".")
PLACEHOLDER_DATES <- c("1900-01-01", "1970-01-01", "9999-12-31", "1899-12-30")
NA_STRINGS <- c("", "NA", "N/A", "n/a", "#N/A", "NULL", "null", "NaN", "nan", "None")
BENCHMARK_BAR <- 97.0

`%||%` <- function(a, b) if (is.null(a)) b else a

# ----------------------------------------------------------------------------- helpers
wilson_ci <- function(successes, n, z = 1.96) {
  if (n == 0) return(c(NA_real_, NA_real_))
  p <- successes / n
  denom <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / denom
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom
  c(max(0, centre - half) * 100, min(1, centre + half) * 100)
}

num_or_null <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x) || !is.finite(x)) return(NULL)
  round(as.numeric(x), 4)
}

load_table <- function(path, nrows = NULL) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("csv", "txt", "tsv")) {
    sep <- if (ext == "tsv") "\t" else ","
    n_max <- if (is.null(nrows)) Inf else nrows
    if (requireNamespace("data.table", quietly = TRUE)) {
      df <- tryCatch(
        data.table::fread(path, sep = sep, colClasses = "character", na.strings = NA_STRINGS,
                          nrows = n_max, data.table = FALSE, encoding = "UTF-8"),
        error = function(e) data.table::fread(path, sep = sep, colClasses = "character",
                                              na.strings = NA_STRINGS, nrows = n_max,
                                              data.table = FALSE, encoding = "Latin-1"))
    } else {
      df <- utils::read.csv(path, sep = sep, colClasses = "character", na.strings = NA_STRINGS,
                            check.names = FALSE, stringsAsFactors = FALSE,
                            nrows = if (is.null(nrows)) -1L else nrows)
    }
    return(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE))
  }
  if (ext %in% c("xlsx", "xls")) {
    if (!requireNamespace("readxl", quietly = TRUE)) stop("Install readxl to read Excel files.")
    df <- as.data.frame(readxl::read_excel(path, n_max = if (is.null(nrows)) Inf else nrows))
  } else if (ext == "parquet") {
    if (!requireNamespace("arrow", quietly = TRUE)) stop("Install arrow to read parquet files.")
    df <- as.data.frame(arrow::read_parquet(path))
    if (!is.null(nrows)) df <- utils::head(df, nrows)
  } else if (ext %in% c("json", "jsonl")) {
    df <- if (ext == "jsonl") jsonlite::stream_in(file(path), verbose = FALSE) else jsonlite::fromJSON(path)
    df <- as.data.frame(df)
    if (!is.null(nrows)) df <- utils::head(df, nrows)
  } else {
    stop(sprintf("Unsupported file type: .%s", ext))
  }
  df[] <- lapply(df, function(x) {
    x <- as.character(x)
    x[x %in% NA_STRINGS] <- NA_character_
    x
  })
  df
}

load_rules <- function(path) {
  if (is.null(path)) {
    return(list(placeholders = DEFAULT_PLACEHOLDERS, columns = list(), cross_field = list()))
  }
  rules <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  rules[["placeholders"]] <- if (is.null(rules[["placeholders"]])) DEFAULT_PLACEHOLDERS else unlist(rules[["placeholders"]])
  if (is.null(rules[["columns"]])) rules[["columns"]] <- list()
  if (is.null(rules[["cross_field"]])) rules[["cross_field"]] <- list()
  rules
}

# True where the raw value is a sentinel masquerading as data (not already null).
is_placeholder <- function(s, placeholders) {
  txt <- trimws(s)
  mask <- !is.na(s) & txt %in% placeholders
  num_sentinels <- suppressWarnings(as.numeric(placeholders[grepl("^-?[0-9]+(\\.[0-9]+)?$", placeholders)]))
  nums <- suppressWarnings(as.numeric(txt))
  mask <- mask | (!is.na(nums) & nums %in% num_sentinels)
  mask <- mask | (!is.na(s) & substr(txt, 1, 10) %in% PLACEHOLDER_DATES)
  mask[is.na(mask)] <- FALSE
  mask
}

parse_dates <- function(x) {
  out <- as.Date(rep(NA_character_, length(x)))
  nn <- !is.na(x)
  if (!any(nn)) return(out)
  y <- substr(trimws(x[nn]), 1, 10)
  d <- as.Date(y, format = "%Y-%m-%d")
  miss <- is.na(d)
  if (any(miss)) d[miss] <- as.Date(y[miss], format = "%d/%m/%Y")
  miss <- is.na(d)
  if (any(miss)) d[miss] <- as.Date(y[miss], format = "%Y/%m/%d")
  out[nn] <- d
  out
}

parse_num <- function(x) suppressWarnings(as.numeric(x))

# Parse date/number columns named in rules (and the date column); opportunistically parse the rest.
coerce <- function(df, col_rules, date_col) {
  parsed <- df
  parse_fail <- list()
  for (col in names(col_rules)) {
    if (!(col %in% names(parsed))) next
    t <- col_rules[[col]][["type"]]
    if (identical(t, "date")) {
      conv <- parse_dates(df[[col]])
      parse_fail[[col]] <- sum(is.na(conv) & !is.na(df[[col]]))
      parsed[[col]] <- conv
    } else if (identical(t, "number")) {
      conv <- parse_num(df[[col]])
      parse_fail[[col]] <- sum(is.na(conv) & !is.na(df[[col]]))
      parsed[[col]] <- conv
    }
  }
  if (!is.null(date_col) && date_col %in% names(parsed) && !inherits(parsed[[date_col]], "Date")) {
    parsed[[date_col]] <- parse_dates(df[[date_col]])
  }
  for (col in names(parsed)) {
    if (col %in% names(col_rules) || identical(col, date_col)) next
    if (!is.character(parsed[[col]])) next
    nn <- sum(!is.na(df[[col]]))
    if (nn == 0) next
    num <- parse_num(df[[col]])
    if (sum(!is.na(num)) == nn) { parsed[[col]] <- num; next }
    if (grepl("(date|_dt$|time)", col, ignore.case = TRUE)) {
      conv <- parse_dates(df[[col]])
      if (sum(!is.na(conv)) >= 0.8 * nn) parsed[[col]] <- conv
    }
  }
  list(parsed = parsed, parse_fail = parse_fail)
}

# ----------------------------------------------------------------------------- IDA
bimodality_hint <- function(x) {
  x <- x[!is.na(x)]
  nun <- length(unique(x))
  n <- length(x)
  if (n < 30 || sd(x) == 0 || nun < 20 || nun / n > 0.9) return(NULL)
  z <- (x - mean(x)) / sd(x)
  skew <- mean(z^3)
  kurt <- mean(z^4) - 3
  bc <- (skew^2 + 1) / (kurt + 3 * (n - 1)^2 / ((n - 2) * (n - 3)))
  list(bimodality_coefficient = round(bc, 3), possible_multimodal = bc > 0.555)
}

initial_data_analysis <- function(raw, parsed, placeholders) {
  n <- nrow(raw)
  out <- list(n_rows = n, n_cols = ncol(raw),
              memory_mb = round(as.numeric(utils::object.size(raw)) / 1e6, 2),
              columns = list(), empty_columns = character(0), constant_columns = character(0),
              high_cardinality_columns = character(0), full_row_duplicates = sum(duplicated(raw)))
  today <- Sys.Date()
  for (col in names(raw)) {
    s <- raw[[col]]
    ps <- parsed[[col]]
    ph <- is_placeholder(s, placeholders)
    nn <- sum(!is.na(s))
    distinct <- length(unique(s[!is.na(s)]))
    info <- list(dtype = class(ps)[1], non_null = nn,
                 null_pct = if (n) round(100 * (1 - nn / n), 2) else NULL,
                 placeholder_count = sum(ph), distinct = distinct)
    if (nn == 0) out$empty_columns <- c(out$empty_columns, col)
    else if (distinct == 1) out$constant_columns <- c(out$constant_columns, col)
    if (is.character(ps) && nn > 0 && distinct / nn > 0.95 && distinct > 50)
      out$high_cardinality_columns <- c(out$high_cardinality_columns, col)
    if (is.numeric(ps) && nn > 0) {
      q <- stats::quantile(ps, c(0.01, 0.5, 0.99), na.rm = TRUE, names = FALSE)
      info$numeric <- list(min = num_or_null(min(ps, na.rm = TRUE)), p01 = num_or_null(q[1]),
                           median = num_or_null(q[2]), p99 = num_or_null(q[3]),
                           max = num_or_null(max(ps, na.rm = TRUE)), mean = num_or_null(mean(ps, na.rm = TRUE)),
                           std = num_or_null(sd(ps, na.rm = TRUE)))
      info["bimodality_hint"] <- list(bimodality_hint(ps))
    } else if (inherits(ps, "Date") && any(!is.na(ps))) {
      info$date_range <- I(as.character(c(min(ps, na.rm = TRUE), max(ps, na.rm = TRUE))))
      info$future_dates <- sum(ps > today, na.rm = TRUE)
    } else {
      vc <- sort(table(s[!is.na(s)]), decreasing = TRUE)
      vc <- utils::head(vc, 8)
      info$top_values <- as.list(stats::setNames(as.integer(vc), names(vc)))
    }
    out$columns[[col]] <- info
  }
  out$empty_columns <- I(out$empty_columns)
  out$constant_columns <- I(out$constant_columns)
  out$high_cardinality_columns <- I(out$high_cardinality_columns)
  out
}

# ----------------------------------------------------------------------------- rules / errors
# Translate pandas-style cross-field expressions into R so one rules.json serves both implementations.
translate_expr <- function(e) {
  id <- "[A-Za-z_][A-Za-z0-9_]*"
  e <- gsub(sprintf("\\b(%s)\\.isna\\(\\)", id), "is.na(\\1)", e, perl = TRUE)
  e <- gsub(sprintf("\\b(%s)\\.notna\\(\\)", id), "!is.na(\\1)", e, perl = TRUE)
  e <- gsub("\\(([^()]*)\\)\\.dt\\.days", "as.numeric(\\1)", e, perl = TRUE)
  e <- gsub("\\.isin\\(\\[([^]]*)\\]\\)", " %in% c(\\1)", e, perl = TRUE)
  e <- gsub("~", "!", e, fixed = TRUE)
  e <- gsub("\\bTrue\\b", "TRUE", e, perl = TRUE)
  e <- gsub("\\bFalse\\b", "FALSE", e, perl = TRUE)
  e
}

top_values_string <- function(x, k = 5) {
  x <- x[!is.na(x)]
  if (!length(x)) return(character(0))
  as.character(names(utils::head(sort(table(x), decreasing = TRUE), k)))
}

apply_rules <- function(raw, parsed, critical, rules, parse_fail) {
  n <- nrow(raw)
  placeholders <- rules[["placeholders"]]
  errors <- list(); weak <- list(); col_results <- list()
  today <- Sys.Date()

  for (col in critical) {
    if (!(col %in% names(raw))) {
      col_results[[col]] <- list(missing_column = TRUE)
      errors[[paste0(col, ": column missing")]] <- rep(TRUE, n)
      next
    }
    r <- rules[["columns"]][[col]]
    if (is.null(r)) r <- list()
    s_raw <- raw[[col]]
    s <- parsed[[col]]
    ph <- is_placeholder(s_raw, placeholders)
    missing <- is.na(s_raw) | ph
    res <- list(null_count = sum(is.na(s_raw)), placeholder_count = sum(ph),
                completeness_pct = if (n) round(100 * (1 - sum(missing) / n), 2) else NULL)
    not_null <- if (is.null(r[["not_null"]])) TRUE else isTRUE(r[["not_null"]])
    if (not_null) errors[[paste0(col, ": missing/placeholder")]] <- missing

    if (!is.null(parse_fail[[col]]) && parse_fail[[col]] > 0) {
      bad <- is.na(s) & !is.na(s_raw) & !ph
      errors[[sprintf("%s: unparseable %s", col, r[["type"]] %||% "value")]] <- bad
      res$unparseable <- sum(bad)
    }
    if (!is.null(r[["allowed"]])) {
      allowed <- as.character(unlist(r[["allowed"]]))
      bad <- !is.na(s_raw) & !ph & !(s_raw %in% allowed)
      errors[[paste0(col, ": not in allowed values")]] <- bad
      res$invalid_values <- sum(bad)
      res$invalid_examples <- I(top_values_string(s_raw[bad]))
    }
    if (!is.null(r[["flag_values"]])) {
      w <- !is.na(s_raw) & s_raw %in% as.character(unlist(r[["flag_values"]]))
      weak[[paste0(col, ": weak/proxy value")]] <- w
      res$weak_values <- sum(w)
    }
    if (!is.null(r[["regex"]])) {
      pat <- paste0("^(?:", r[["regex"]], ")$")
      bad <- !is.na(s_raw) & !ph & !grepl(pat, s_raw, perl = TRUE)
      errors[[paste0(col, ": regex mismatch")]] <- bad
      res$regex_mismatch <- sum(bad)
    }
    lo <- r[["min"]]; hi <- r[["max"]]
    if (!is.null(lo) || !is.null(hi)) {
      if (inherits(s, "Date")) {
        conv <- function(v) if (identical(v, "today")) today else as.Date(v)
      } else if (is.numeric(s)) {
        conv <- function(v) as.numeric(v)
      } else {
        conv <- NULL
      }
      if (!is.null(conv)) {
        bad <- rep(FALSE, n)
        if (!is.null(lo)) bad <- bad | (!is.na(s) & s < conv(lo))
        if (!is.null(hi)) bad <- bad | (!is.na(s) & s > conv(hi))
        errors[[paste0(col, ": out of range")]] <- bad
        res$out_of_range <- sum(bad)
        res$range <- I(c(as.character(lo %||% "None"), as.character(hi %||% "None")))
      }
    }
    if (isTRUE(r[["unique"]])) {
      dup <- !is.na(s_raw) & duplicated(s_raw)
      errors[[paste0(col, ": duplicate value")]] <- dup
      res$duplicates <- sum(dup)
    }
    col_results[[col]] <- res
  }

  for (cf in rules[["cross_field"]]) {
    expr_src <- cf[["r_expr"]] %||% translate_expr(cf[["expr"]] %||% "")
    name <- cf[["name"]] %||% cf[["expr"]] %||% cf[["r_expr"]]
    key <- paste0("rule: ", name)
    result <- tryCatch({
      ok <- eval(parse(text = expr_src), envir = parsed, enclos = baseenv())
      if (length(ok) == 1) ok <- rep(ok, n)
      if (length(ok) != n) stop("expression did not return one value per row")
      # Rows with a missing value in any referenced column pass this rule: missingness is already counted
      # by the column rules, and comparisons with NA silently propagate NA.
      referenced <- names(parsed)[vapply(names(parsed), function(cn)
        grepl(paste0("(?<![A-Za-z0-9_.])", gsub("([.|()\\^{}+$*?\\[\\]\\\\])", "\\\\\\1", cn), "(?![A-Za-z0-9_])"),
              expr_src, perl = TRUE), logical(1))]
      has_na <- if (length(referenced)) Reduce(`|`, lapply(referenced, function(cn) is.na(parsed[[cn]]))) else rep(FALSE, n)
      list(key = key, fail = (!as.logical(ok)) & !is.na(ok) & !has_na)
    }, error = function(e) list(key = paste0(key, " (FAILED TO EVALUATE: ", conditionMessage(e), ")"),
                                fail = rep(FALSE, n)))
    errors[[result$key]] <- result$fail
  }

  err_df <- if (length(errors)) as.data.frame(errors, check.names = FALSE, optional = TRUE) else data.frame(row.names = seq_len(n))
  weak_df <- if (length(weak)) as.data.frame(weak, check.names = FALSE, optional = TRUE) else data.frame(row.names = seq_len(n))
  list(err_df = err_df, weak_df = weak_df, col_results = col_results)
}

perfect_record_score <- function(err_df) {
  n <- nrow(err_df)
  if (n == 0 || ncol(err_df) == 0) return(list(n_records = n, perfect_records = n, score_pct = NULL, ci95_pct = NULL))
  any_err <- rowSums(err_df) > 0
  perfect <- sum(!any_err)
  ci <- wilson_ci(perfect, n)
  list(n_records = n, perfect_records = perfect, defective_records = n - perfect,
       score_pct = round(100 * perfect / n, 2), ci95_pct = I(round(ci, 2)),
       meets_97_bar = ci[1] >= BENCHMARK_BAR,
       errors_per_defective_record = if (perfect < n) round(mean(rowSums(err_df)[any_err]), 2) else 0,
       redman_benchmark = paste("Across 75 organisations (Nagle, Redman & Sammon 2017): half of scores below 57%,",
                                "a quarter below 30%, 3% at or above 97%."))
}

pareto <- function(err_df) {
  if (ncol(err_df) == 0) return(list())
  counts <- sort(colSums(err_df), decreasing = TRUE)
  counts <- counts[counts > 0]
  total <- sum(counts)
  cum <- 0
  rows <- list()
  for (nm in names(counts)) {
    cum <- cum + counts[[nm]]
    rows[[length(rows) + 1]] <- list(error_type = nm, count = counts[[nm]],
                                     share_pct = round(100 * counts[[nm]] / total, 2),
                                     cumulative_pct = round(100 * cum / total, 2))
  }
  rows
}

# ----------------------------------------------------------------------------- variation
# Defect proportion per group with 3-sigma limits (variable n). Flags out-of-control groups.
p_chart <- function(defective, groups, label) {
  ok <- !is.na(groups)
  if (!any(ok)) return(NULL)
  g <- as.character(groups[ok]); d <- as.integer(defective[ok])
  keys <- sort(unique(g))
  sums <- as.vector(tapply(d, g, sum)[keys]); cnt <- as.vector(tapply(d, g, length)[keys])
  pbar <- sum(sums) / sum(cnt)
  p <- sums / cnt
  sigma <- sqrt(pbar * (1 - pbar) / cnt)
  ucl <- pmin(1, pbar + 3 * sigma); lcl <- pmax(0, pbar - 3 * sigma)
  ooc <- (p > ucl) | (p < lcl)
  rows <- lapply(seq_along(keys), function(i) {
    r <- list()
    r[[label]] <- keys[i]
    c(r, list(n = cnt[i], defective = sums[i], defect_rate_pct = round(100 * p[i], 2),
              ucl_pct = round(100 * ucl[i], 2), lcl_pct = round(100 * lcl[i], 2), out_of_control = ooc[i]))
  })
  list(centre_line_pct = round(100 * pbar, 2), n_groups = length(keys),
       out_of_control_groups = I(keys[ooc]), range_pct = I(round(100 * range(p), 2)), rows = rows)
}

date_spikes <- function(dates, factor = 10, min_count = 20) {
  d <- dates[!is.na(dates)]
  if (!length(d)) return(NULL)
  vc <- sort(table(as.character(d)), decreasing = TRUE)
  med <- stats::median(as.numeric(vc))
  sp <- vc[vc > factor * max(med, 1) & vc >= min_count]
  sp <- utils::head(sp, 15)
  list(median_records_per_day = med, n_days = length(vc),
       spikes = lapply(seq_along(sp), function(i)
         list(date = names(sp)[i], count = as.integer(sp[i]), x_median = round(as.numeric(sp[i]) / max(med, 1), 1))),
       future_dates = sum(dates > Sys.Date(), na.rm = TRUE), missing_dates = sum(is.na(dates)))
}

period_key <- function(dates, period) {
  out <- rep(NA_character_, length(dates))
  ok <- !is.na(dates)
  yr <- format(dates[ok], "%Y")
  out[ok] <- switch(toupper(period),
    Y = yr,
    Q = paste0(yr, "Q", (as.integer(format(dates[ok], "%m")) - 1) %/% 3 + 1),
    M = format(dates[ok], "%Y-%m"),
    stop("--period must be M, Q or Y"))
  out
}

missingness_trend <- function(parsed, critical, pkey) {
  present <- intersect(critical, names(parsed))
  if (!length(present) || all(is.na(pkey))) return(NULL)
  keys <- sort(unique(pkey[!is.na(pkey)]))
  res <- lapply(keys, function(k) {
    idx <- which(pkey == k)
    as.list(stats::setNames(vapply(present, function(c) round(100 * mean(is.na(parsed[[c]][idx])), 2), numeric(1)), present))
  })
  stats::setNames(res, keys)
}

# ----------------------------------------------------------------------------- FAM worksheet
fam_worksheet <- function(raw, parsed, err_df, critical, date_col, n, out_dir) {
  present <- intersect(critical, names(raw))
  if (!is.null(date_col) && date_col %in% names(parsed)) {
    idx <- utils::tail(order(parsed[[date_col]], na.last = FALSE), n)
  } else {
    idx <- utils::tail(seq_len(nrow(raw)), n)
  }
  ws <- raw[idx, present, drop = FALSE]
  flags <- if (ncol(err_df)) vapply(idx, function(i) paste(names(err_df)[unlist(err_df[i, ])], collapse = "; "), "")
           else rep("", length(idx))
  ws <- cbind(`_record_index` = idx, ws, `_auto_flags` = flags, perfect_record = "", reviewer_notes = "",
              stringsAsFactors = FALSE)
  path <- file.path(out_dir, "fam_worksheet.csv")
  utils::write.csv(ws, path, row.names = FALSE, na = "")
  list(path = path, n = nrow(ws))
}

# ----------------------------------------------------------------------------- plots
make_plots <- function(result, out_dir) {
  made <- character(0)
  save_png <- function(file, width, height, expr) {
    p <- file.path(out_dir, file)
    ok <- tryCatch({
      grDevices::png(p, width = width * 130, height = height * 130, res = 130)
      on.exit(grDevices::dev.off(), add = TRUE)
      force(expr)
      TRUE
    }, error = function(e) FALSE)
    if (ok) made <<- c(made, p)
  }

  pr <- result$pareto
  if (length(pr)) {
    top <- utils::head(pr, 12)
    cnt <- vapply(top, function(r) as.numeric(r$count), numeric(1))
    cum <- vapply(top, function(r) r$cumulative_pct, numeric(1))
    lab <- substr(vapply(top, function(r) r$error_type, ""), 1, 38)
    save_png("pareto.png", 9, 4.5, {
      graphics::par(mar = c(15, 4, 3, 4))
      bp <- graphics::barplot(cnt, names.arg = lab, las = 2, cex.names = 0.7, col = "#4a6fa5",
                              ylab = "errors", main = "Error Pareto (critical data elements)")
      usr <- graphics::par("usr")
      graphics::par(new = TRUE)
      graphics::plot(bp, cum, type = "b", pch = 16, col = "#c0504d", axes = FALSE, ann = FALSE,
                     ylim = c(0, 105), xlim = usr[1:2], xaxs = "i")
      graphics::axis(4); graphics::mtext("cumulative %", side = 4, line = 2.5)
    })
  }

  for (spec in list(c("by_period", "pchart.png", "Defect rate by period (p-chart, 3-sigma limits)"),
                    c("by_group", "funnel.png", "Defect rate by group (3-sigma limits)"))) {
    pc <- result$variation[[spec[1]]]
    if (is.null(pc) || !length(pc$rows)) next
    rows <- pc$rows
    lab <- vapply(rows, function(r) as.character(r[[1]]), "")
    rate <- vapply(rows, function(r) r$defect_rate_pct, numeric(1))
    ucl <- vapply(rows, function(r) r$ucl_pct, numeric(1))
    lcl <- vapply(rows, function(r) r$lcl_pct, numeric(1))
    ooc <- vapply(rows, function(r) isTRUE(r$out_of_control), logical(1))
    save_png(spec[2], 9, 4.5, {
      graphics::par(mar = c(7, 4, 3, 1))
      graphics::plot(seq_along(rate), rate, type = "b", pch = 16, col = "#4a6fa5", xaxt = "n",
                     ylim = range(c(rate, ucl, lcl)), xlab = "", ylab = "% defective records", main = spec[3])
      graphics::axis(1, at = seq_along(lab), labels = lab, las = 2, cex.axis = 0.7)
      graphics::lines(seq_along(ucl), ucl, lty = 2, col = "#c0504d")
      graphics::lines(seq_along(lcl), lcl, lty = 2, col = "#c0504d")
      graphics::abline(h = pc$centre_line_pct, col = "grey")
      if (any(ooc)) graphics::points(which(ooc), rate[ooc], pch = 19, col = "#c0504d", cex = 1.6)
      graphics::legend("topright", c("defect rate %", "limits", "centre"), lty = c(1, 2, 1),
                       col = c("#4a6fa5", "#c0504d", "grey"), cex = 0.7, bty = "n")
    })
  }

  comp <- result$critical_columns
  cols <- names(comp)[vapply(comp, function(v) !is.null(v$completeness_pct), logical(1))]
  if (length(cols)) {
    vals <- vapply(cols, function(c) comp[[c]]$completeness_pct, numeric(1))
    save_png("completeness.png", 8, 0.4 * length(cols) + 1.5, {
      graphics::par(mar = c(4, 10, 3, 1))
      graphics::barplot(rev(vals), names.arg = rev(cols), horiz = TRUE, las = 1, xlim = c(0, 100),
                        col = "#4a6fa5", xlab = "% complete (non-null, non-placeholder)",
                        main = "Completeness of critical data elements")
      graphics::abline(v = BENCHMARK_BAR, col = "#c0504d", lty = 2)
    })
  }
  made
}

# ----------------------------------------------------------------------------- summary
write_summary <- function(result, out_dir) {
  s <- result$perfect_record_score
  L <- character(0)
  add <- function(...) L <<- c(L, paste0(...))
  add("# Data quality profile: ", basename(result$source), "\n")
  add(sprintf("Rows: %s  Columns: %d  Critical data elements: %d\n",
              format(result$ida$n_rows, big.mark = ","), result$ida$n_cols, length(result$critical)))
  if (!is.null(s$score_pct)) {
    add(sprintf("## Perfect-record score: **%s%%** (95%% CI %s to %s)\n", s$score_pct, s$ci95_pct[1], s$ci95_pct[2]))
    add(sprintf("%s of %s records have no error in any critical element. Bar: %s%% (Redman's loosest acceptable standard). %s the bar. %s\n",
                format(s$perfect_records, big.mark = ","), format(s$n_records, big.mark = ","), BENCHMARK_BAR,
                if (s$meets_97_bar) "Meets" else "Does not meet", s$redman_benchmark))
    add("This automated score counts only errors a rule anticipated; it is a lower bound on the true error rate. ",
        "Do the human pass on the FAM worksheet to catch the rest.\n")
    if (is.null(result$rules_file)) {
      add("**No rules file was supplied**, so the score reflects missing values and placeholders only. ",
          "Write a rules.json from the data customer's error definitions (ranges, allowed values, ",
          "cross-field checks) and re-run; see references/rules-format.md.\n")
    }
  }
  add("## Critical data elements\n")
  add("| Column | Completeness % | Nulls | Placeholders | Invalid | Out of range | Duplicates | Weak/proxy |")
  add("|---|---|---|---|---|---|---|---|")
  for (c in names(result$critical_columns)) {
    v <- result$critical_columns[[c]]
    if (isTRUE(v$missing_column)) { add("| ", c, " | COLUMN MISSING | | | | | | |"); next }
    inv <- v$invalid_values %||% v$regex_mismatch %||% ""
    add("| ", c, " | ", v$completeness_pct, " | ", v$null_count, " | ", v$placeholder_count, " | ", inv, " | ",
        v$out_of_range %||% "", " | ", v$duplicates %||% "", " | ", v$weak_values %||% "", " |")
  }
  add("")
  if (length(result$pareto)) {
    add("## Error Pareto\n")
    add("| Error type | Count | Share % | Cumulative % |")
    add("|---|---|---|---|")
    for (r in utils::head(result$pareto, 15)) add("| ", r$error_type, " | ", r$count, " | ", r$share_pct, " | ", r$cumulative_pct, " |")
    add("")
  }
  ida <- result$ida
  add("## Initial data analysis flags\n")
  add("- Full-row duplicates: ", ida$full_row_duplicates)
  if (!is.null(result$key_duplicates)) add("- Duplicate keys on `", result$key, "`: ", result$key_duplicates)
  if (length(ida$empty_columns)) add("- Empty columns: ", paste(ida$empty_columns, collapse = ", "))
  if (length(ida$constant_columns)) add("- Constant columns: ", paste(ida$constant_columns, collapse = ", "))
  ph <- Filter(function(n) n > 0, vapply(ida$columns, function(v) as.numeric(v$placeholder_count), numeric(1)))
  if (length(ph)) add("- Placeholder values found: ", paste(sprintf("%s (%d)", names(ph), as.integer(ph)), collapse = ", "))
  bim <- names(Filter(function(v) isTRUE(v$bimodality_hint$possible_multimodal), ida$columns))
  if (length(bim)) add("- Possibly multimodal numeric columns (check for unit or definition mixes): ", paste(bim, collapse = ", "))
  fut <- Filter(function(n) n > 0, vapply(ida$columns, function(v) as.numeric(v$future_dates %||% 0), numeric(1)))
  if (length(fut)) add("- Future dates: ", paste(sprintf("%s (%d)", names(fut), as.integer(fut)), collapse = ", "))
  add("")
  var <- result$variation
  if (!is.null(var$by_period)) {
    pc <- var$by_period
    add("## Stability over time (p-chart)\n")
    add(sprintf("- Centre line %s%% defective across %d periods; range %s%% to %s%%.",
                pc$centre_line_pct, pc$n_groups, pc$range_pct[1], pc$range_pct[2]))
    add("- Out-of-control periods: ", if (length(pc$out_of_control_groups)) paste(pc$out_of_control_groups, collapse = ", ") else "none", "\n")
  }
  if (!is.null(var$by_group)) {
    pc <- var$by_group
    add("## Variation across units\n")
    add(sprintf("- Centre line %s%% defective across %d groups; range %s%% to %s%%.",
                pc$centre_line_pct, pc$n_groups, pc$range_pct[1], pc$range_pct[2]))
    add("- Groups outside 3-sigma limits: ", if (length(pc$out_of_control_groups)) paste(pc$out_of_control_groups, collapse = ", ") else "none", "\n")
  }
  if (length(var$date_spikes$spikes)) {
    add("## Date spikes (possible batch or retrospective entry)\n")
    for (sp in var$date_spikes$spikes) add(sprintf("- %s: %d records (%sx the daily median)", sp$date, sp$count, sp$x_median))
    add("")
  }
  add("## What this script cannot tell you\n")
  add("- Accuracy against reality (needs a reference source or the human FAM pass).")
  add("- Whether this is the right data for the decision (population match, pedigree, definitions).")
  add("- Records that should exist but do not (coverage, false negatives).")
  add("\nFAM worksheet: ", result$fam_worksheet, "  Charts: ",
      if (length(result$plots)) paste(basename(result$plots), collapse = ", ") else "none", "\n")
  path <- file.path(out_dir, "dq_summary.md")
  writeLines(L, path, useBytes = TRUE)
  path
}

# ----------------------------------------------------------------------------- main
usage <- function() {
  cat("Usage: Rscript dq_profile.R <data> --critical a,b,c [--rules rules.json] [--key id1,id2]\n",
      "       [--date-col d] [--period M|Q|Y] [--group-col g] [--fam-sample 100] [--out dq_output]\n",
      "       [--nrows N] [--no-plots]\n", sep = "")
}

parse_args <- function(argv) {
  a <- list(data = NULL, critical = NULL, rules = NULL, key = NULL, date_col = NULL, period = "Q",
            group_col = NULL, fam_sample = 100L, out = "dq_output", nrows = NULL, no_plots = FALSE)
  known <- c("critical", "rules", "key", "date_col", "period", "group_col", "fam_sample", "out", "nrows")
  i <- 1
  while (i <= length(argv)) {
    tok <- argv[i]
    if (tok %in% c("-h", "--help")) { usage(); quit(status = 0) }
    if (tok == "--no-plots") {
      a[["no_plots"]] <- TRUE
    } else if (startsWith(tok, "--")) {
      nm <- substring(tok, 3); val <- NULL
      if (grepl("=", nm, fixed = TRUE)) { val <- sub("^[^=]*=", "", nm); nm <- sub("=.*$", "", nm) }
      nm <- gsub("-", "_", nm)
      if (!(nm %in% known)) stop("Unknown option: ", tok)
      if (is.null(val)) { i <- i + 1; val <- argv[i] }
      a[[nm]] <- val
    } else if (is.null(a[["data"]])) {
      a[["data"]] <- tok
    }
    i <- i + 1
  }
  if (is.null(a[["data"]])) { usage(); stop("A data file is required.") }
  if (is.null(a[["critical"]])) stop("--critical is required.")
  a[["fam_sample"]] <- as.integer(a[["fam_sample"]])
  if (!is.null(a[["nrows"]])) a[["nrows"]] <- as.integer(a[["nrows"]])
  a
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  a <- parse_args(argv)
  dir.create(a$out, showWarnings = FALSE, recursive = TRUE)
  raw <- load_table(a$data, a$nrows)
  rules <- load_rules(a$rules)
  critical <- trimws(strsplit(a$critical, ",", fixed = TRUE)[[1]])
  critical <- critical[nzchar(critical)]
  missing_cols <- setdiff(critical, names(raw))
  if (length(missing_cols)) message("WARNING: critical columns not in data: ", paste(missing_cols, collapse = ", "))

  cz <- coerce(raw, rules[["columns"]], a$date_col)
  parsed <- cz$parsed
  ida <- initial_data_analysis(raw, parsed, rules[["placeholders"]])
  ar <- apply_rules(raw, parsed, critical, rules, cz$parse_fail)
  err_df <- ar$err_df
  n <- nrow(raw)

  key_cols <- character(0); key_dups <- NULL
  if (!is.null(a$key)) {
    key_cols <- intersect(trimws(strsplit(a$key, ",", fixed = TRUE)[[1]]), names(raw))
    if (length(key_cols)) {
      key_dup_mask <- duplicated(raw[, key_cols, drop = FALSE])
      key_dups <- sum(key_dup_mask)
      # a duplicate key is a record-level defect: fold it into the score and the Pareto
      err_df[[sprintf("key duplicate (%s)", paste(key_cols, collapse = "+"))]] <- key_dup_mask
    }
  }
  score <- perfect_record_score(err_df)
  par <- pareto(err_df)
  defective <- if (ncol(err_df)) rowSums(err_df) > 0 else rep(FALSE, n)

  variation <- structure(list(), names = character(0))
  has_date <- !is.null(a$date_col) && a$date_col %in% names(parsed) && inherits(parsed[[a$date_col]], "Date")
  pkey <- NULL
  if (has_date) {
    dts <- parsed[[a$date_col]]
    pkey <- period_key(dts, a$period)
    variation["by_period"] <- list(p_chart(defective, pkey, "period"))
    variation["date_spikes"] <- list(date_spikes(dts))
    variation["missingness_by_period_pct"] <- list(missingness_trend(parsed, critical, pkey))
    vol <- table(pkey)
    variation$volume_by_period <- as.list(stats::setNames(as.integer(vol), names(vol)))
  }
  if (!is.null(a$group_col) && a$group_col %in% names(raw)) {
    grp <- raw[[a$group_col]]
    variation["by_group"] <- list(p_chart(defective, grp, "group"))
    if (!is.null(pkey)) {
      ok <- !is.na(grp) & !is.na(pkey)
      tab <- tapply(as.integer(defective[ok]), list(grp[ok], pkey[ok]), mean)
      variation$defect_rate_group_by_period_pct <- lapply(
        stats::setNames(rownames(tab), rownames(tab)),
        function(g) lapply(stats::setNames(colnames(tab), colnames(tab)),
                           function(p) if (is.na(tab[g, p])) NA_real_ else round(100 * tab[g, p], 2)))
    }
  }

  fam <- fam_worksheet(raw, parsed, err_df, critical, a$date_col, a$fam_sample, a$out)

  crit_cols <- ar$col_results
  result <- list(source = normalizePath(a$data, winslash = "/"), critical = I(critical), rules_file = a$rules,
                 key = a$key, key_duplicates = key_dups, date_col = a$date_col, group_col = a$group_col,
                 ida = ida, critical_columns = crit_cols,
                 weak_values = if (ncol(ar$weak_df)) as.list(colSums(ar$weak_df)) else structure(list(), names = character(0)),
                 perfect_record_score = score, pareto = par, variation = variation,
                 fam_worksheet = fam$path, fam_rows = fam$n,
                 benchmarks = list(acceptable_bar_pct = BENCHMARK_BAR, rule_of_ten = "defective inputs cost ~10x to process"))
  result$plots <- I(if (isTRUE(a$no_plots)) character(0) else make_plots(result, a$out))

  json_path <- file.path(a$out, "dq_profile.json")
  jsonlite::write_json(result, json_path, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null", digits = NA)
  summ <- write_summary(result, a$out)
  cat(readLines(summ, warn = FALSE), sep = "\n")
  cat("\nWrote: ", paste(c(json_path, summ, fam$path, result$plots), collapse = ", "), "\n", sep = "")
  invisible(result)
}

if (sys.nframe() == 0L) main()
