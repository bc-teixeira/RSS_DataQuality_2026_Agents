---
name: data-quality-evaluation
description: Evaluate whether a dataset is fit for a specific use and produce an evidence-based data quality report, following the published methods of Tom Redman (Friday Afternoon Measurement, perfect-record score, rule of ten, fix at source), Roger Hoerl (data pedigree, statistical thinking, "right data" vs "data are right", SPC on data) and Rosemary Tate (tiered definitions, triangulation, unit-by-period metrics, failure patterns, initial data analysis). Use this skill whenever someone asks to check, assess, profile, validate, audit or QC a dataset, table, extract, feed, registry, EHR or claims data, or asks "can I trust this data", "is this data good enough for X", "what's wrong with this file", or wants a data quality plan, checklist, scorecard, monitoring design or FAM exercise. Trigger even when the user only says "have a look at this CSV before I model it" or "sanity-check the extract" and does not say "data quality".
---

# Data Quality Evaluation

Data quality is **fitness for use**. A dataset is never good or bad in the abstract; it is fit, or not, for one
decision or analysis. Redman and Hoerl split the question in two, and so does this skill:

| Question | Meaning | Who answers it |
|---|---|---|
| **Right data?** | Does this data, collected the way it was, bear on *this* problem? Population, variables, timeframe, measurement. | Pedigree, domain knowledge, sensitivity analyses |
| **Data are right?** | Are the values accurate, complete, consistent, current, unique, valid? | Profiling, rules, record-level scoring, reference checks |

Most "DQ checks" only do the second. Redman's survey of 75 organisations found half of datasets below 57%
perfect records and only 3% meeting a 97% standard, so expect to find problems. But Hoerl's warning is the one
teams skip: *many data sets are simply not worth analysing* because they were collected for another purpose.
Say so when it is true.

## Workflow

Work through the seven steps below in order. Steps 1 and 2 need no code and take minutes; skipping them is the
single most common failure in DQ work ("everyone wants to do the model work, not the data work", Tate and Halliday).

### Step 1. Frame the use and the data customer

Before touching the file, write down:

- **The decision or analysis** the data must support, in one sentence. If the user has not said, ask or state
  the assumption prominently. "Fit for many uses" is not "fit for this use" (the 2020 US Census was fit for
  funding allocation but not for apportionment).
- **The data customer**: who consumes the result. Redman: the customer is the final arbiter of quality.
  Definitions of "critical" and "error" come from them, not from generic rules.
- **Critical data elements (CDEs)**: the 10 to 15 fields the decision cannot survive without. Everything else is
  secondary. Record them explicitly; the perfect-record score in Step 5 is computed over exactly these.
- **What "error" means per CDE**: missing, implausible, out of range, inconsistent with another field, stale,
  duplicated. Write the operational definition. Vague definitions produce unreproducible scores.
- **The acceptance standard**: Redman's loosest acceptable bar is 97% perfect records. Agree the bar with the
  customer; a regulatory submission and an exploratory dashboard do not share one.

### Step 2. Establish the data pedigree

Hoerl and Snee: a pedigree documents "samples, measurement processes utilized, and the subsequent handling of the
data, including any modifications or deletions made, through the present". Answer who / what / when / where /
why / how, from the user, documentation, or the data itself:

- **Origin and purpose of collection.** Operational system, survey, registry, claims, instrument? Data collected
  for billing or incentive payments (Tate's QOF example) will reflect the incentive, not the clinical truth.
- **Sampling and population.** How did units enter the dataset? Does the sampled population match the population
  the decision is about? For prediction, the population of interest is *future* cases.
- **Exclusions and transformations.** What was dropped, merged, imputed, recoded, and when? Ask for the raw
  extract. The Challenger O-ring analysis failed because zero-failure flights were excluded.
- **Measurement system.** Instrument, protocol, who records, how much judgement. Hoerl's blood-pressure case:
  wrong cuff size alone produced 39% false positives. If you can, estimate repeatability and reproducibility.
- **Handling since.** Spreadsheets, manual re-keying, legacy migrations and free-text fields are where Tate's
  "Spreadsheet Cascade" and "Proxy Trap" patterns live.

Record unknowns as unknowns. An unanswered pedigree question is itself a finding.

Read `references/pedigree-questions.md` for the full question list when the data is unfamiliar.

### Step 3. Initial data analysis (look before you score)

Tate's "data detectives" rule: run cheap exploratory checks before any modelling or scoring, because they catch
what rules cannot anticipate (a column-only Excel sort was caught by a correlation matrix; a protocol change was
caught by two outliers in a cluster plot). Do, and record:

- Shape, types, memory; columns that are entirely null, constant, or have suspiciously high cardinality.
- Distributions of every CDE: histograms or quantiles, top values, min/max. Look for **placeholder values**
  (`999`, `-1`, `1900-01-01`, `UNKNOWN`, blank strings) masquerading as data, and for **bimodality** that
  signals mixed units or mixed definitions.
- **Time-ordered plots** of volume and of each CDE's missingness and mean. Hoerl's statistical thinking: separate
  systematic, random and outlier variation; establish stability before computing anything that assumes it.
- **Date spikes**: many records sharing one entry date usually means batch or retrospective entry with wrong
  dates (Tate found this in CPRD).
- Correlations and cross-tabs between fields that should agree (type vs treatment, diagnosis vs test).
- **Treat outliers as evidence to explain, never as noise to delete.** Hoerl: they may be measurement errors, or
  the most valuable points in the set.

The bundled script does most of this mechanically; the judgement about what the patterns mean is yours.

### Step 4. Run the bundled profiler

```
python scripts/dq_profile.py <data.csv|parquet|xlsx> \
    --critical col1,col2,col3 \
    [--rules rules.json] [--key patient_id] \
    [--date-col visit_date] [--period M|Q|Y] [--group-col site] \
    [--fam-sample 100] [--out dq_output]
```

An R port with identical checks, options, outputs and `rules.json` is available as `scripts/dq_profile.R`
(`Rscript scripts/dq_profile.R <data> --critical ...`; needs only `jsonlite`). Use whichever language the user's
team works in; on the test files both produce the same score, Pareto and flagged units. Apart from the
`_record_index` in the FAM worksheet being 1-based in R, the outputs are interchangeable.

It writes `dq_profile.json` (everything), `dq_summary.md` (human summary), `fam_worksheet.csv`
(the last N records across the CDEs, with auto-flags and a blank `perfect_record` column for human review), and
`pchart.png` / `pareto.png` / `completeness.png` when matplotlib is available. Build a `rules.json` from Step 1's
error definitions; see `references/rules-format.md` for the schema (ranges, allowed values, regex, date bounds,
uniqueness, and cross-field expressions such as `~((dm_type == 'T1') & (insulin_rx == 0))`).

If the data lives in a database, pull a representative extract (recent records plus a stratified historical sample)
to a file first; scoring the most recent 100 to 1,000 records is the Friday Afternoon Measurement in Redman's
original form and is informative on its own.

### Step 5. Score "data are right" by dimension and at record level

Report each dimension separately, then the record-level score:

| Dimension | What to compute | Source |
|---|---|---|
| Completeness | Share non-null and non-placeholder per CDE; completeness of study-specific tests or fields | Redman; Tate (JAMIA 2014) |
| Validity / plausibility | Share of values inside allowed ranges or code lists; Tate measures accuracy as the proportion of implausible values | Tate (Dungey 2014) |
| Accuracy | Agreement with a reference: gold standard, linked source, free text, physical reality. If none exists, say accuracy is **unmeasured**, not fine | Redman FAM step 6; Tate internal vs external validation |
| Consistency / concordance | Cross-field rules (death after diagnosis, type vs treatment), cross-source agreement, definition reconciliation when merging | Hoerl big-data "missing links"; Tate triangulation |
| Timeliness / currency | Lag between event and record; share of stale records; recording-date vs event-date gaps | Tate (free text predates code by months) |
| Uniqueness | Duplicate keys and duplicate rows; near-duplicates | Redman |

Then the **perfect-record score**: the percentage of records with *no* error in *any* CDE. Redman insists on this
unit rather than average field accuracy, because a record with one wrong critical field is unusable downstream.
Give a confidence interval (the script uses Wilson). Compare with the 97% bar and with Redman's benchmark
distribution (half of real datasets fall below 57%).

Rank error types with a **Pareto**. The top two or three error types usually carry most of the defects and point
at root causes.

### Step 6. Assess "right data", variation and stability

- **Sensitivity across definitions.** Tate's method: build tiered definitions (definite, ambiguous, proxy)
  and re-run the headline estimate under each. If the answer moves materially, the data cannot settle the
  question without further validation. Report the spread, not one number.
- **Variation across units, not just the average.** Compute defect rates by site, practice, source, vendor,
  period. Redman and Hoerl's census lesson: the average miscount was small, the state-to-state variation changed
  the outcome. Use a p-chart or funnel plot; flag units outside control limits.
- **Stability over time.** Shifts in volume, missingness, code mix or distributions over time are "Silent Drift"
  until proven otherwise. Trend by category to expose incentive or policy artefacts. Compute the per-unit,
  per-period mean and spread of every measured CDE, not only defect rates: a **step change confined to one unit
  from one date** is a measurement-system or process change (new analyser, method, protocol, software, coding
  rule, vendor) until the unit says otherwise. Name that hypothesis, say what to ask the unit, and do not
  attribute the step to case mix or noise without evidence. Hoerl's hypertension column and the census
  Post-Enumeration Survey are both cases where the measurement, not the population, moved.
- **Population match.** Compare the dataset's demographics, geography and time coverage against the target
  population of the decision. Flag coverage gaps as "right data" failures even when every value is accurate.
- **Self-referencing benchmarks.** If the only external benchmark is derived from the same recording system,
  say so; agreement proves little.

### Step 7. Verdict, root causes and recommendations

Deliver the report using the template below (full version in `references/report-template.md`). Essentials:

- **Verdict in Redman's triage**: *fit for this use*, *fit with stated caveats*, or *not fit*. Lead with it.
- **Cost it.** Redman's rule of ten: a unit of work costs ten times as much on defective input as on perfect
  input. Translate the defect rate into rework, delay or decision risk for this customer. Even a rough number
  changes behaviour.
- **Name the failure pattern** where one applies (Tate's taxonomy): Silent Drift, Proxy Trap, Spreadsheet
  Cascade, Governance Vacuum, Metric Mirage. Naming it points to the kind of fix.
- **Fix at source versus clean.** Redman's three modes are unmanaged, organised clean-up, proactive prevention.
  Cleaning is a stop-gap; for each top Pareto error, say where in the creating process it enters and who owns
  that step. Recommend prevention first, cleaning second.
- **Controls going forward.** Repeat the measurement on a schedule; chart the perfect-record rate (SPC); add
  checkpoints that stop unvalidated data flowing downstream; make error rates visible beside the performance
  metrics the data feeds.
- **Transparency.** List every limitation and unknown, including what the script could not assess (accuracy
  against reality, pedigree gaps). Tate and Halliday argue initial data analysis should be reported; do it.

## Report template

Keep the headings; drop sections that genuinely do not apply and say why.

```markdown
# Data quality evaluation: <dataset> for <intended use>

## Verdict
<Fit / Fit with caveats / Not fit> for <use>. Perfect-record score X% (95% CI a to b) against a 97% bar
over N critical data elements. One-paragraph justification.

## Intended use and data customer
## Data pedigree (who, what, when, where, why, how; unknowns listed)
## Initial data analysis findings
## Scores by dimension (table) and record-level score
## Error Pareto (top error types, counts, share, likely origin)
## Variation and stability (by unit, over time; out-of-control points)
## Right-data assessment (population match, definition sensitivity, coverage)
## Cost and risk of the defects (rule of ten applied)
## Root causes and failure pattern
## Recommendations (prevent at source; clean; controls and monitoring; owners)
## Limitations and what was not assessed
## Appendix: rules used, script outputs, FAM worksheet location
```

## When the user wants a plan, not an evaluation

If there is no dataset yet, or the request is "how should we check this feed going forward", produce a
measurement system rather than a report:

1. **Friday Afternoon Measurement** as the first move (Redman): last 100 records, 10 to 15 CDEs, two or three
   people who know the data, two hours, mark errors in red, count perfect records. Optionally validate 20 records
   against reality. Full procedure in `references/redman.md`.
2. **Pedigree capture** for every new source (Step 2 questions as a form).
3. **Automated rules** derived from the customer's error definitions, run on every load, with the perfect-record
   rate charted over time and control limits. If the team will run the bundled profiler, copy
   `scripts/dq_profile.py` into their deliverable folder next to the rules file and runbook; a plan that
   imports it from the skill path will not run on their machines.
4. **Checkpoints** that block downstream flow when the rate breaches the limit, plus an independent QA sample
   (the census Post-Enumeration Survey idea: a second, independent measurement of the same thing).
5. **Ownership and feedback loops**: a named owner per CDE, errors fed back to creators, a no-blame "data
   amnesty" so errors surface (Tate and Halliday).
6. **Re-evaluation on reuse**: checks tuned for one purpose do not transfer; schedule a fresh Step 1 whenever the
   data gets a new customer.

## Keep the effort proportionate

The workflow is a checklist of questions, not a mandate to build tooling. One profiler run over the agreed CDEs
plus a few targeted pandas checks answers most evaluations; a second run is justified only when the verdict
depends on it (for instance, core versus extended CDE sets giving different answers). Do not write a bespoke
monitoring framework, wrapper scripts, or multi-file template packs unless the user asked for a system to run
repeatedly. When they did ask for a plan, a two-page runbook, a rules file and the bundled profiler are usually
the right size; a statistician should be able to run the whole thing in an afternoon. Spend the saved effort on
the parts the script cannot do: pedigree, right-data reasoning, root causes and a verdict the customer can act on.

## Judgement rules that distinguish good DQ work

- Lead with fitness for the stated use. A long list of findings with no verdict is not an evaluation.
- Score records, not just fields. Report the percentage of perfect records with an interval.
- Never report an average without the variation across units and over time.
- Unmeasured is not the same as fine. Say which dimensions you could not assess.
- Explain outliers; do not delete them. Flag placeholder values; do not treat them as data.
- Prefer prevention at the creating process over cleaning the output, and say who owns the process step.
- Be willing to conclude "this data cannot answer this question", and say what data could.
- Keep the raw extract untouched; work on copies; record every transformation you apply.

## Reference files

| File | Read when |
|---|---|
| `references/redman.md` | Running or explaining FAM, perfect-record scoring, rule of ten, hidden data factory, three modes, customer-supplier model |
| `references/hoerl.md` | Writing a pedigree, statistical-thinking checks, SPC on data, "right data" questions for AI/ML training sets, statistical twin |
| `references/tate.md` | Health records, registries, coded data, tiered definitions, triangulation with prescriptions/tests/free text, unit-by-period metrics, failure patterns |
| `references/pedigree-questions.md` | The full who/what/when/where/why/how interview for an unfamiliar source |
| `references/rules-format.md` | Building `rules.json` for the profiler |
| `references/report-template.md` | The full report template with guidance per section |
| `references/bibliography.md` | Citable sources with URLs for every method used above |
