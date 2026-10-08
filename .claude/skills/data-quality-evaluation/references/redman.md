# Tom Redman: measuring and managing data quality

Thomas C. Redman ("the Data Doc", Data Quality Solutions) built the managerial school of data quality from his
Bell Labs work in the late 1980s onward. His contribution to *evaluation* is a small set of simple, repeatable
measurements and a vocabulary that connects them to cost and to the processes that create data.

## 1. Friday Afternoon Measurement (FAM)

Source: HBR, "Assess Whether You Have a Data Quality Problem" (July 2016); Nagle, Redman and Sammon, HBR
"Only 3% of Companies' Data Meets Basic Quality Standards" (Sept 2017) and *Business Horizons* 63(3) 2020;
Redman's Medium series *Data Quality is for Everyone!*, chapter 4.

Procedure, as published:

1. Assemble the **last 100 records** your group used or created. Recent records matter because they reflect the
   process as it runs today.
2. Pick the **10 to 15 critical data elements** (the ones the work cannot proceed without).
3. Invite **two or three people who know the data** to a **two-hour** meeting (Friday afternoon, when work slows).
4. Lay the records out as a spreadsheet, one row per record, one column per CDE. **Working record by record,
   mark obvious errors in red.** Obvious means a knowledgeable person can see the value is wrong without
   looking anything up.
5. Add a column **"perfect record"**. A record is perfect only if **no** critical field is marked.
6. **Count the perfect records.** That number, 0 to 100, is the **Data Quality (DQ) score**: the percentage of
   records created correctly.
7. Optional extensions: validate a 20-record subset against the real world or another system to catch
   non-obvious accuracy errors; add a per-field "correct" column to obtain field-level error rates.
8. Estimate the impact with the **rule of ten** (below) and extrapolate to the team's workload.

Benchmarks for interpretation:

| Statistic | Value | Source |
|---|---|---|
| Loosest acceptable standard | 97% perfect records | HBR 2017 |
| Datasets meeting that standard | 3% of 75 | HBR 2017 |
| Average share of records with at least one critical error | 47% | HBR 2017 |
| Half of DQ scores below | 57% | HBR 2017 |
| A quarter of DQ scores below | 30% | HBR 2017 |
| Range observed | 0% to 99% | HBR 2017 |

Why the record is the unit: a record with one wrong critical field cannot be used as-is, so field-level
accuracy averages hide the real failure rate. Ten fields each 95% accurate give roughly 60% perfect records.

Automating FAM: the same arithmetic over an extract (null, placeholder, or rule-violating CDE = error) gives
an *automated* score. It under-counts, because it only sees errors a rule anticipated; treat it as a lower bound
on the error rate and still do the human pass on a sample.

## 2. Rule of ten and the hidden data factory

- **Rule of ten** (HBR 2016): "it costs ten times as much to complete a unit of work when the input data are
  defective as it does when they are perfect." Use it to turn a DQ score into money or time: with a 70% score,
  30 of every 100 units cost 10x, so total cost is roughly 70 + 300 = 370 units against 100 for perfect data.
- **Hidden data factory** (HBR Sept 2016, "Bad Data Costs the U.S. $3 Trillion Per Year"): the added steps
  people take to hunt for data, find and correct errors, and search for confirmatory sources. Redman's
  benchmarks: knowledge workers waste about 50% of their time this way; data scientists spend about 60% of their
  time cleaning and organising (CrowdFlower survey). Auditing this time is a cost measure of poor quality.
- MIT SMR 2017 "Seizing Opportunity in Data Quality": cost of bad data runs 15% to 25% of revenue for most
  companies.

## 3. Customer-supplier model

Data are created by processes and consumed by **data customers**; the people who run the creating processes are
**data creators**. "Quality is in the eyes of the customer": the customer is the final arbiter of what counts as
critical and what counts as an error. Redman's field finding is that "in almost every situation, a root cause of
poor data quality was that data creators did not understand the needs of important data customers."

Evaluation consequences:

- Define CDEs and error definitions **with the customer**, then measure. Generic rule packs measure the wrong thing.
- When the top Pareto error traces to a creator, the fix is usually communication of requirements, not software.
- "Trust triage" (HBR 2015, "Can Your Data Be Trusted?"): classify each source as bad and unusable; good and
  trustworthy; or flawed but usable with caution, and document which.

## 4. Fix at the source, not just clean

- HBR 2013 "Data's Credibility Problem": "the only good way to address data quality is to create data correctly
  the first time" by "finding and eliminating the root causes of error in the business processes that create
  the data."
- HBR 2020 "To Improve Data Quality, Start at the Source": most organisations clean rather than prevent.
- MIT SMR 2025 (El Maarry and Redman) "How to Get Proactive About Data Quality": three modes of operation,
  **unmanaged**, **organised clean-up**, **proactive prevention**. Only the third reduces the error rate over time.
- Classic quality tools transfer directly (Redman 1992, 1996): **p-charts** of the fraction defective per period,
  **Pareto charts** of error types, and **data tracking** (follow a sample of records through the operational
  process to find the step where errors enter).

## 5. Roles

*Getting in Front on Data* (2016) and *People and Data* (2023): everyone is both a data customer and a data
creator. **Data provocateurs** are the people who start measuring and asking questions; FAM is their opening move.
**Embedded data managers** help teams run measurements and improvements. Managers, not IT, own data quality.

## 6. Data quality for analytics and AI

- HBR 2018 "If Your Data Is Bad, Your Machine Learning Tools Are Useless": bad data hits twice, in the training
  data and in the production data the model scores. Prescriptions: confirm you have the *right* data for the
  problem before worrying whether it is error-free; build DQ time into the plan; keep an audit trail of
  training-data preparation; name an accountable owner; get independent, rigorous QA.
- MIT SMR 2023 (Hoerl and Redman) "What Managers Should Ask About AI Models and Data Sets": ask "are these the
  *right* data for this problem?" before "are the data correct?"; available data were usually collected for
  another purpose.
- MIT SMR 2024 (Redman and Hoerl) "AI and Statistics: Perfect Together": AI has no basis for inference about
  data collected under different circumstances; sampling theory, designed tests of deployed models, a
  **statistical twin** (an interpretable model run alongside the ML model to find sub-populations where either
  fails), and SPC on deployed models supply one.
- HBR 2024 "Ensure High-Quality Data Powers Your AI": understand the problem; get the data right (right data and
  error-free); assign responsibility now; push quality upstream for the long term.
- HBR 2025 (Davenport, Hoerl, Redman) on unstructured data: "less is more" curation, humans in the loop, test
  until the application works, feed lessons back to content creation.

## 7. Redman's evaluation checklist

1. Measure before you argue: run FAM on the last 100 records over 10 to 15 CDEs.
2. Score at record level; report % perfect against a 97% bar and the benchmark distribution.
3. Let the data customer define "critical" and "error".
4. Convert the score to cost with the rule of ten; audit the hidden data factory.
5. Validate a subset against reality (accuracy) and against other systems (consistency).
6. Pareto the error types; chase the top few to root cause in the creating process.
7. Repeat and chart (p-chart). Build a measurement system, not a one-off.
8. For analytics and AI: right data first, then error-free; audit trail; independent QA; both training and
   production data under control.
9. Move from clean-up to prevention; name an accountable owner; empower provocateurs.
