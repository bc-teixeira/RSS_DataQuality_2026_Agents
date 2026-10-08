# Rosemary Tate: data quality in routinely collected and coded data

Dr A. Rosemary Tate (Chartered Statistician; formerly Brighton and Sussex Medical School and University of
Sussex; RSS AI Task Force) spent a decade measuring data quality in UK primary-care databases (GPRD/CPRD) and now
writes the RSS Real World Data Science "Data Quality Under the Lens" column. Her work is the most concrete
guide available for evaluating electronic health records, registries, claims and any other data captured as
codes by busy people under incentives.

Her framework uses the UK Audit Commission's six dimensions: **accuracy, validity, reliability, timeliness,
relevance, completeness**, with measures "tailored to the intended use of the data" (Dungey et al. 2014).

## 1. Fitness for use drives which measures you compute

Tate et al., *JAMIA* 21(2) 2014 (TrialViz): "data quality, which we define as fitness for use, is a sine qua non".
Method: take the study protocol, identify the variables the study needs, and for each relevant dimension compute
**simple ratios** (desired outcomes / total) per **practice per year**: general measures (missing dates, missing
codes) and study-specific measures (completeness of the relevant test results, e.g. HbA1c for a diabetes study).
Then "distributions of these variables and their interrelationships were investigated using summary statistics,
graphs (histograms, boxplots and scatterplots) and correlation analysis." Select units on two criteria: the
suitability of the patient base and the quality of recording. Prefer time-indexed, unit-level scores over a
single binary "up to standard" flag (Tate et al. 2011).

Accuracy, where no gold standard exists, is operationalised as the **proportion of implausible values**.

## 2. Tiered definitions and sensitivity analysis

Tate et al., *BMC Medical Research Methodology* 9:42 (2009), ovarian cancer: four increasingly inclusive
definitions of first diagnosis (definite diagnosis; ambiguous diagnosis; first treatment or complication implying
a diagnosis; first relevant test or referral). Re-estimate the outcome under each and report the spread.
"Studies which date diagnoses in GP records need to present sensitivity analyses based on investigation,
referral and diagnosis data."

Tate et al., *BMJ Open* 7:e012905 (2017), diabetes in CPRD: a hierarchical code list with certainty categories
(Type 1 diagnostic code; Type 2 diagnostic code; diagnostic code of unspecified type; proxy codes such as "seen
in diabetic clinic"). Compute incidence per category per year. **Trend by category**: the post-2006 surge was
driven by proxy codes, an artefact of the Quality and Outcomes Framework incentive, not of disease.

Nicholson, Tate et al., *Pharmacoepidemiology and Drug Safety* 20(3) 2011: a sevenfold variation in rheumatoid
arthritis incidence was attributable to code-list differences; "sensitivity analyses to investigate the impact of
code choice on study results should become standard practice."

## 3. Triangulation and explicit misclassification rules

From the diabetes study (adapting de Lusignan's algorithm), rules that flag records and score units:

- Type 1 never prescribed insulin: likely misclassified.
- Type 2 prescribed insulin within 6 months of diagnosis: likely misclassified.
- Type 2 with no insulin, no oral antidiabetic, no abnormal glucose and no abnormal HbA1c: unsupported diagnosis.
- Oral antidiabetic (excluding metformin) prescribed with no diabetes diagnosis: **false negative**.
- Only vague or proxy codes: **miscoded**.
- A practice is "poor" if at least 10% of its cases are flagged. Re-run the analysis with poor practices excluded
  and report the change (15% of 666 practices were poor; the trend changed).
- "Proxy codes should be confirmed with test results and prescribing information." "Reporting error measurements
  to account for miscoding and misclassification should be included in future studies."

Free text as arbiter (BMJ Open 2011; Ford et al. 2013): for ovarian cancer, 22% of patients had text confirming
the diagnosis before the code, 10% more than four weeks earlier, 4 coded patients did not have the disease, and
10% had only an ambiguous diagnosis behind a definite code. For rheumatoid arthritis, keywords preceded the code
in 29% of patients, joint symptoms by a median of 133 days. Use this to measure **currency** (lag between event
and record) and **correctness**.

## 4. Internal versus external validation

Nicholson, Tate et al. 2011: separate "Did the recorder think the patient had this condition?" (internal
validation, confirmation) from "Was the recorder correct?" (external validation against a gold standard such as
hospital or registry linkage). Estimate **false negatives** by comparing database rates with external sources.
Beware selection bias when validation relies on units that volunteer. And note **self-referencing benchmarks**:
if official statistics are themselves built from the same codes, agreement with them proves little.

## 5. Checks that catch recording artefacts

- **Date spikes**: practices with many new cases on one date are usually entering codes retrospectively with the
  wrong date.
- **Registration windows**: exclude cases with less than 365 days (or 2 years) of registration before the index
  date, so prevalent cases are not counted as incident.
- **Incentive and policy breakpoints**: check trends around known changes (QOF 2004 and 2006 in UK primary care;
  any coding-system migration, payment-rule change or software upgrade in other domains).
- **Benchmark recorded frequencies against the literature** (recorded symptom rates were far below self-report
  studies, a completeness signal).
- Publish code lists and extraction code so others can reproduce the definitions.

## 6. The data-detective culture and the failure patterns

Tate and Halliday, "Why We Should All Be Data Quality Detectives" (RWDS, Oct 2025; RSS 2025 workshop):

- Why quality is neglected: "everyone wants to do the model work, not the data work"; discomfort with the
  unquantifiable; Harford's "premature enumeration"; no clear ownership; the assumption that someone else checked.
- Do **initial data analysis** before modelling (two outlier spectra exposed a protocol change; a correlation
  matrix exposed a column-only spreadsheet sort). Keep raw-data backups. Checks tuned to one purpose do not
  transfer: **re-evaluate quality on every reuse**.
- Workshop recommendations: training across roles; transparent reporting of errors and limitations; feedback
  loops to data collectors; rewarding error detection; using AI and automation to support checks; journals
  requiring initial data analysis reporting; a no-blame **"data amnesty"**.

Tate, "Data Quality Under the Lens: UK Prison Release Errors" (RWDS, May 2026) introduced five failure
patterns used across the column:

| Pattern | Meaning | Typical evidence |
|---|---|---|
| **Silent Drift** | Quality degrades gradually with no alarm | Trends in missingness, code mix, distributions; out-of-control p-chart points |
| **Proxy Trap** | A convenient proxy is treated as the thing itself | Proxy codes, popularity of a dataset mistaken for quality, incentive-driven recording |
| **Spreadsheet Cascade** | Manual handling propagates an error downstream | Column-only sorts, re-keying, version confusion, copy-paste ranges |
| **Governance Vacuum** | Nobody owns the data or the gap | No CDE owner, no acceptance standard, no feedback loop |
| **Metric Mirage** | The measurement system misleads | Device and operator variation, wrong protocol, unit mix, bimodal distributions |

Practitioner takeaways from the same column: "Don't just track outputs; measure uncertainty: missing data,
overrides, corrections, and inconsistencies." "Design for verification, not just speed. Build checkpoints that
prevent unvalidated data from flowing downstream." "Regularly trace records back to their origin, especially where
legacy or paper systems are involved." "Make data quality visible. Surface error rates and data gaps alongside
performance metrics."

Tate, Hunsicker and Osei, "Small Data, High Quality" (RWDS, Aug 2026): a small high-quality dataset beats a
massive poor one; measure label error rates in training and test sets (benchmark datasets carry about 3.3% label
errors and complex models memorise them); define what "good" looks like per use case; keep a human in the loop;
agentic pipelines amplify early errors across steps.

## 7. Tate's evaluation checklist

1. State the intended use; derive the study-specific variables from the protocol; measure each relevant dimension.
2. Build tiered definitions (definite, ambiguous, proxy); run every estimate under each tier; report the spread.
3. Triangulate codes with prescriptions, tests and free text; write explicit rules for misclassification, false
   negatives and vague-only cases.
4. Compute unit-by-period ratio metrics; inspect distributions and correlations graphically; score units and
   report the effect of excluding poor ones.
5. Examine time trends per category for incentive or policy artefacts and date spikes.
6. Separate internal from external validation; beware self-referencing benchmarks.
7. Use free text (or any independent record) as arbiter for dating and misclassification.
8. Do initial data analysis before modelling; keep raw data; re-assess on reuse; report quality transparently.
