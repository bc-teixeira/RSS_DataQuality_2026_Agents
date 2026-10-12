# Reproduction Protocol: MDLA Critical-Care Mortality Study

## Source study

**Patel K, Beedala P.** *Unmeasured but Not Unbiased: The Missingness Demographic Leakage Audit (MDLA) for Calibration-Aware Fairness Evaluation in Critical Care Mortality Prediction.* medRxiv. Posted May 3, 2026.

- DOI: https://doi.org/10.64898/2026.05.01.26352193
- Development database: MIMIC-IV v2.2
- External validation database: eICU Collaborative Research Database v2.0
- Status: Preprint; not peer reviewed
- Reporting framework: TRIPOD+AI

> **Purpose of this document**
>
> This is a structured, reproducibility-oriented protocol reconstructed from the published Methods. It is a paraphrased protocol, not a verbatim copy of the paper. It is intended for research-methods and data-quality testing, including use with the 100-patient MIMIC-IV Demo v2.2.

---

# 1. Study objective

The study evaluates whether patterns of missing clinical measurements in ICU data encode demographic information and whether prediction models may rely on those missingness patterns in ways that create or amplify subgroup performance disparities.

The study has four main objectives:

1. Characterize whether patterns of missing clinical measurements predict demographic group membership.
2. Determine whether a mortality prediction model relies on those missingness patterns.
3. Evaluate predictive performance and fairness across demographic and clinical subgroups.
4. Compare post-hoc recalibration strategies and assess transportability to an external ICU database.

For a small-dataset reproduction using the 100-patient MIMIC-IV demo, the primary reproducible objective should be:

> **Construct the study cohort, extract first-24-hour predictors, quantify data completeness and missingness patterns, and reproduce as much of the MDLA workflow as sample size permits.**

---

# 2. Study design

- Retrospective observational cohort study.
- Development cohort: MIMIC-IV v2.2.
- External validation cohort: eICU-CRD v2.0.
- Unit of analysis: one eligible ICU stay per patient.
- Prediction target: in-hospital mortality.
- Predictor ascertainment window: first 24 hours from ICU admission.
- Random seed used in the published study: **42**.

All preprocessing parameters, imputation statistics, operating thresholds, and model decisions are derived from the development data and then applied without modification to later validation data.

---

# 3. Data source

## 3.1 Primary development database

**MIMIC-IV v2.2**

Single-center de-identified critical-care database from Beth Israel Deaconess Medical Center, Boston, Massachusetts.

Relevant domains include:

- patient demographics;
- hospital admissions;
- ICU stays;
- vital-sign/chart events;
- laboratory results;
- urine output;
- diagnosis information used to derive comorbidity burden;
- mortality outcome.

For the conference demonstration, the **MIMIC-IV Clinical Database Demo v2.2** can be used. It contains 100 patients and preserves the core schema of the full database.

## 3.2 External validation database

**eICU Collaborative Research Database v2.0**

Used in the original study for external validation. External validation is optional for the 100-patient demonstration and is not required to test the data-quality workflow.

---

# 4. Study population

## 4.1 Inclusion criteria

Include ICU stays meeting **all** of the following:

1. Patient age **>=18 years** at ICU admission.
2. ICU length of stay **>=4 hours**.
3. In-hospital mortality outcome is available.
4. The ICU stay is the **first ICU stay within the selected hospital admission**.
5. The hospital admission is the **first hospital admission for that patient**.

The original MIMIC-IV cohort contained **50,827 ICU stays** after applying these criteria.

## 4.2 Exclusion criteria

Exclude:

- patients younger than 18 years;
- ICU stays shorter than 4 hours;
- records without a usable in-hospital mortality outcome;
- subsequent ICU stays during the same hospital admission;
- subsequent hospital admissions for the same patient.

## 4.3 Index selection logic

The intended hierarchy is:

```text
patient
  -> first hospital admission
      -> first ICU stay in that admission
```

Thus each patient contributes at most one analytical observation.

---

# 5. Index date and observation window

## Index time

The index time is the ICU admission timestamp.

## Predictor window

Clinical predictors are extracted from:

```text
ICU admission time <= event time <= ICU admission time + 24 hours
```

Measurements outside this window should not contribute to predictor derivation.

This 24-hour restriction is an important **fitness-for-purpose data-quality rule** and should be explicitly validated.

---

# 6. Outcome

## Primary outcome

**In-hospital mortality**

Binary outcome:

```text
1 = patient died during the index hospital admission
0 = patient survived the index hospital admission
```

The outcome must be non-missing for cohort eligibility.

For MIMIC-IV implementation, the hospital-level mortality indicator should be linked to the selected index hospital admission.

---

# 7. Predictor set

The final published model contains **43 predictors**:

- 20 vital-sign-derived predictors;
- 21 laboratory predictors;
- 2 clinical composite predictors.

Before exclusion of troponin, 44 candidate clinical features were considered for the missingness audit.

---

# 8. Vital-sign predictors

Clinical measurements are obtained during the first 24 hours after ICU admission.

The seven vital-sign domains reported in the paper are:

1. Heart rate
2. Systolic blood pressure
3. Mean arterial pressure
4. Respiratory rate
5. Peripheral oxygen saturation (SpO2)
6. Temperature
7. Glasgow Coma Scale total

Repeated measurements are summarized using combinations of:

- minimum;
- maximum;
- mean.

The manuscript reports **20 derived vital-sign features in total**.

> **Reproduction note**
>
> Seven domains multiplied by three summary statistics would nominally produce 21 features. The manuscript nevertheless reports 20 vital-sign predictors. The exact vital/statistic combination responsible for this difference should be verified against the authors' released analysis code or supplementary material rather than inferred.

---

# 9. Laboratory predictors

Twenty-two laboratory concepts were initially considered. Troponin was excluded from the final clinical predictor matrix because it was reported as 100% missing in the training data, leaving **21 laboratory predictors**:

1. Creatinine
2. Blood urea nitrogen (BUN)
3. Lactate
4. Hemoglobin
5. Hematocrit
6. Platelets
7. White blood cell count
8. Sodium
9. Potassium
10. Bicarbonate
11. Chloride
12. Glucose
13. PaO2
14. PaCO2
15. pH
16. ALT
17. AST
18. Bilirubin
19. Albumin
20. INR
21. PTT

Troponin remains relevant to construction of the missingness-indicator matrix even though it is excluded from the final 43-value clinical predictor matrix.

Repeated laboratory measurements should be summarized according to the study's feature-extraction implementation within the first 24-hour window.

---

# 10. Clinical composite predictors

Two additional predictors are included:

## 10.1 Twenty-four-hour urine output

Total urine output during the first 24 hours after ICU admission.

Data-quality checks should include:

- temporal inclusion within the 24-hour window;
- valid linkage to the index ICU stay;
- duplicate output records;
- implausible negative values;
- unit consistency;
- completeness of recording.

## 10.2 Elixhauser comorbidity count

Comorbidity burden derived from diagnosis data.

For the MIMIC development cohort this is included as a predictor.

---

# 11. Physiological plausibility filtering

Laboratory measurements are filtered using clinically defined plausibility ranges before modelling.

Examples explicitly provided in the paper include:

- Creatinine: **0.1–30 mg/dL**
- pH: **6.5–8.0**

The full set of variable-specific plausibility limits should be recovered from the authors' code before attempting an exact reproduction.

For the data-quality demonstration, plausibility checking should be treated as a separate stage from missingness assessment:

```text
raw value
 -> unit validation
 -> plausibility validation
 -> aggregation
 -> missingness indicator
```

---

# 12. Demographic variables

## 12.1 Race and ethnicity

Harmonized to five groups:

- White
- Black
- Hispanic
- Asian
- Other

## 12.2 Sex

Used as a subgroup axis in fairness analyses.

## 12.3 Insurance

Mapped to:

- Medicare
- Medicaid
- Other/Unknown

Insurance analyses were performed only in MIMIC-IV because eICU does not contain equivalent insurance information.

## 12.4 Age strata

Age was categorized as:

- 18–44
- 45–64
- 65–74
- >=75 years

Age was not used as a primary fairness axis in the published fairness evaluation because age is considered a clinically legitimate mortality predictor.

## 12.5 ICU type

Harmonized into six groups:

- MICU
- SICU
- CCU
- NICU
- TSICU
- Other

---

# 13. Missingness Demographic Leakage Audit (MDLA)

Missingness indicators are created **before imputation**.

For candidate feature `X`:

```text
miss_X = 1 if X is absent
miss_X = 0 if X is observed
```

The study constructs **44 binary missingness indicators**, including the troponin indicator.

## Step 1 — Construct missingness indicators

Create one binary indicator for each initially defined candidate feature before imputation.

## Step 2 — Demographic predictability from missingness

Use only the missingness indicators as predictors.

Train multinomial logistic regression models to predict:

- race/ethnicity group;
- insurance category.

Evaluation:

- 5-fold cross-validation;
- macro-averaged one-vs-rest AUROC;
- confidence intervals calculated using the Hanley-McNeil variance approach.

The conceptual question is:

> Can the pattern of what clinicians chose to measure, or not measure, predict patient demographic characteristics?

## Step 3 — Feature-level missingness associations

For each testable missingness indicator:

- calculate a chi-square test of independence versus racial group;
- quantify effect size with Cramer's V;
- correct for multiple testing using Bonferroni adjustment.

The troponin missingness indicator is excluded from this association-testing step because it is constant in the training data.

Number of association tests:

**43**

Statistical significance:

```text
Bonferroni-corrected p < 0.05
```

## Step 4 — Model-reliance ablation

Retrain XGBoost using:

```text
43 clinical predictors
+
44 missingness indicators
=
87 model inputs
```

Compare this model with the standard clinical-feature model.

Primary MDLA ablation quantity reported in the paper:

- change in racial AUROC disparity.

The purpose is to determine whether exposing the model explicitly to measurement-absence patterns changes subgroup disparities even when global predictive performance changes little.

---

# 14. Missing-data preprocessing

For the standard prediction models:

1. Determine median values using the **training partition only**.
2. Median-impute missing clinical values using those training-derived medians.
3. Apply those same medians unchanged to validation and test data.

The published study explicitly retains simple median imputation so that the incremental effect of explicit missingness indicators can be isolated.

---

# 15. Development-data partitioning

The MIMIC-IV development cohort is divided into:

- **70% training**
- **15% internal validation**
- **15% internal test**

Splitting is stratified on mortality prevalence.

Published sample sizes:

- Training: 35,578
- Validation: 7,624
- Test: 7,625

Random seed:

**42**

> **100-patient demo note**
>
> Reproducing these exact partitions with approximately 100 patients is statistically fragile. For the conference demonstration, cohort construction and data-quality assessment should be the primary endpoints. Model-performance and fairness estimates should be labelled exploratory because subgroup counts will be small.

---

# 16. Scaling

## Logistic regression

Apply min-max scaling to the interval:

```text
[0, 1]
```

Scaling parameters must be derived from training data.

## Random forest and XGBoost

Use unscaled predictor values.

---

# 17. Prediction models

Three classifiers are developed:

1. Logistic regression
2. Random forest
3. XGBoost

Hyperparameters are selected using:

- 5-fold stratified grid search;
- optimization target: AUROC.

Classification operating thresholds are selected using the **Youden index** on the internal validation set.

These thresholds are used for study comparisons and are not intended as clinical decision thresholds.

---

# 18. Predictive-performance evaluation

Evaluate:

- AUROC;
- 95% AUROC confidence intervals using 1,000 bootstrap iterations;
- AUPRC;
- Brier score;
- DeLong test for pairwise AUROC comparisons;
- Expected Calibration Error (ECE);
- ECE using 10 uniform probability bins;
- calibration slope;
- calibration intercept.

Classification metrics are calculated using the validation-derived Youden threshold.

---

# 19. Fairness assessment

Five fairness criteria are assessed:

## 19.1 Equalized odds

Evaluate maximum subgroup differences in:

- true-positive rate;
- false-positive rate.

## 19.2 Equal opportunity

Evaluate maximum subgroup difference in true-positive rate.

## 19.3 Demographic parity

Evaluate maximum subgroup difference in positive prediction rate.

## 19.4 Predictive parity

Evaluate maximum subgroup difference in positive predictive value.

## 19.5 Calibration fairness

Evaluate maximum subgroup Expected Calibration Error.

Primary subgroup axes:

- race/ethnicity;
- sex;
- insurance;
- ICU type.

Subgroups with fewer than **30 observations in the test set** are excluded from formal fairness evaluation.

Pairwise subgroup uncertainty is assessed using 1,000 bootstrap iterations for selected metrics.

---

# 20. Post-hoc recalibration

Six XGBoost calibration strategies are compared:

1. Uncalibrated model
2. Global Platt scaling
3. Race-conditional Platt scaling
4. Insurance-conditional Platt scaling
5. Isotonic regression
6. Fairness-aware temperature scaling

Calibration models are fitted on the internal validation partition.

For group-conditional Platt scaling, groups with fewer than **50 validation observations** fall back to global calibration.

The fairness-aware temperature-scaling objective balances:

```text
overall ECE + lambda * maximum subgroup ECE
```

with:

```text
lambda = 0.5
```

Strategies are compared using a fairness-versus-utility Pareto analysis.

---

# 21. External validation

The original study applies the MIMIC-derived workflow to eICU-CRD v2.0 without re-estimating development preprocessing parameters.

The same broad cohort criteria are used.

External validation evaluates:

- predictive discrimination;
- calibration;
- fairness;
- generalization gap;
- distributional shift.

Distributional shift is evaluated across comparable predictors using Kolmogorov-Smirnov testing.

For the 100-patient conference demonstration, this stage can be omitted.

---

# 22. Recommended MIMIC-IV Demo implementation

For the 100-patient dataset, preserve the original population and data-extraction rules but reduce the analytical ambition.

## Required reproduction stages

### Stage A — Cohort construction

Produce an attrition table:

```text
All demo patients
 -> age >=18
 -> first hospital admission
 -> first ICU stay
 -> ICU LOS >=4 h
 -> mortality outcome available
 -> final analytical cohort
```

### Stage B — First-24-hour feature inventory

For every intended predictor determine:

- whether the variable can be mapped to MIMIC;
- source table;
- number of patients with >=1 observation;
- missingness proportion;
- number of observations per patient;
- unit(s);
- minimum;
- maximum;
- implausible-value count;
- temporal violations outside the study window.

### Stage C — Data-quality assessment

Recommended domains:

1. **Conformance**
   - field type;
   - units;
   - coding system;
   - valid identifiers.

2. **Completeness**
   - patient-level feature availability;
   - subgroup missingness;
   - completely absent variables.

3. **Plausibility**
   - physiological ranges;
   - impossible negative values;
   - extreme values.

4. **Temporal integrity**
   - first-24-hour window;
   - admission/ICU sequence;
   - events before ICU admission or after window close.

5. **Relational integrity**
   - patient -> admission;
   - admission -> ICU stay;
   - event -> valid patient/admission/stay.

6. **Uniqueness**
   - duplicate events;
   - duplicate index stays;
   - repeated records with identical timestamp/value.

7. **Fitness for purpose**
   - sufficient observations to calculate each derived feature;
   - sufficient subgroup size;
   - sufficient deaths to fit/evaluate mortality models;
   - feasibility of MDLA and formal fairness analyses.

### Stage D — Missingness audit

Even with the small demo cohort, calculate:

- overall missingness per feature;
- missingness by sex;
- missingness by race/ethnicity where sample sizes allow;
- missingness correlation matrix;
- completely observed and completely missing features.

Formal inferential claims should be avoided when cell counts are very small.

### Stage E — Optional exploratory model

If the final cohort and number of mortality events are adequate:

- fit a simplified logistic model;
- optionally fit XGBoost;
- report performance as illustrative only;
- do not interpret subgroup fairness metrics as stable estimates if subgroup sizes are small.

---

# 23. Core data-quality questions for an autonomous agent

An agent receiving this protocol and the raw database should ideally infer questions such as:

1. Can age at ICU admission be derived reliably?
2. Is the selected ICU stay truly the first stay of the patient's first admission?
3. Are ICU admission and discharge timestamps internally consistent?
4. Does every index ICU stay last at least four hours?
5. Is mortality defined at the correct hospital-admission level?
6. Are all predictor values restricted to the first 24 hours?
7. Are multiple source codes used for the same clinical concept?
8. Are units consistent across those source codes?
9. Which protocol variables cannot be reproduced?
10. Which predictors are completely absent?
11. Which predictors are sparsely measured?
12. Are measurement frequencies different across demographic groups?
13. Are values physiologically plausible?
14. Are impossible or extreme values driving min/max summaries?
15. Are duplicate events present?
16. Do event records link to valid patients, admissions and ICU stays?
17. Is urine output adequately captured throughout the observation window?
18. Can the Elixhauser count be reconstructed from available diagnoses?
19. Are missingness indicators created before imputation?
20. Is the sample size sufficient for the requested modelling and subgroup analyses?

---

# 24. Primary outputs for a reproduction

At minimum produce:

1. Cohort attrition table.
2. Baseline cohort characteristics.
3. Variable-to-database mapping table.
4. Per-feature completeness table.
5. Per-feature plausibility report.
6. Unit-consistency report.
7. Temporal-quality report.
8. Missingness heatmap.
9. Missingness by demographic subgroup.
10. List of protocol requirements that cannot be reproduced.
11. Overall fitness-for-purpose conclusion.
12. Optional exploratory mortality model results.
13. Optional MDLA association/ablation results where sample size permits.

---

# 25. Important limitations for the 100-patient demo

The MIMIC-IV demo is suitable for demonstrating **protocol-aware data-quality assessment**, but not for reproducing the statistical precision of the original study.

Expected limitations include:

- small final ICU cohort;
- small number of deaths;
- very small demographic subgroups;
- unstable train/validation/test estimates;
- inability to conduct reliable subgroup fairness inference;
- possible complete absence of some laboratory variables;
- unreliable 5-fold model-selection procedures;
- very wide or uninterpretable confidence intervals.

Therefore the preferred scientific question for the demo is:

> **Can an autonomous agent correctly determine whether this dataset is fit to reproduce the study, identify the relevant data-quality risks, execute the necessary checks, and explain which parts of the protocol are or are not reproducible?**

This framing is stronger than attempting to claim a valid replication of the mortality/fairness estimates from only 100 patients.

---

# 26. Reproducibility parameters

| Parameter | Published specification |
|---|---|
| Development database | MIMIC-IV v2.2 |
| Population | Adult ICU patients |
| Minimum ICU LOS | 4 hours |
| Index admission | First hospital admission |
| Index ICU stay | First ICU stay |
| Predictor window | First 24 h after ICU admission |
| Outcome | In-hospital mortality |
| Final predictors | 43 |
| Missingness indicators | 44 |
| Training split | 70% |
| Validation split | 15% |
| Test split | 15% |
| Split stratification | Mortality |
| Imputation | Training-set median |
| LR scaling | Min-max [0,1] |
| Random seed | 42 |
| Model selection | 5-fold stratified grid search |
| Optimization metric | AUROC |
| Classification threshold | Youden index |
| ECE bins | 10 |
| Bootstrap iterations | 1,000 |
| Fairness subgroup minimum | n >=30 in test set |
| Group calibration fallback | n <50 -> global calibration |
| Bonferroni tests | 43 |
| Temperature-scaling lambda | 0.5 |

---

# 27. Source and verification note

This document was reconstructed from the methods reported in the May 2026 medRxiv preprint:

Patel K, Beedala P. *Unmeasured but Not Unbiased: The Missingness Demographic Leakage Audit (MDLA) for Calibration-Aware Fairness Evaluation in Critical Care Mortality Prediction.*

DOI: https://doi.org/10.64898/2026.05.01.26352193

Before claiming an exact reproduction, verify against the authors' code and supplementary material:

- exact MIMIC item IDs / variable mappings;
- exact aggregation rule producing the reported 20 vital-sign predictors;
- all variable-specific plausibility ranges;
- exact hyperparameter grids and selected hyperparameters;
- detailed Elixhauser implementation;
- exact urine-output derivation;
- external-validation harmonization rules.

