# Data quality evaluation report template

Use these headings. Each section lists what belongs in it and the source of the practice. Lead with the verdict:
a reader who stops after the first paragraph must know whether to use the data.

```markdown
# Data quality evaluation: <dataset> for <intended use>

## Verdict
```
One of **Fit for this use**, **Fit with caveats** (list them), **Not fit** (say what data would be). Give the
perfect-record score with its 95% interval, the number of CDEs and the acceptance bar, and one paragraph on the
two or three findings that drove the verdict. (Redman trust triage; Redman and Hoerl census case.)

```markdown
## Intended use and data customer
```
The decision in one sentence, who makes it, the CDEs chosen and why, the operational definition of error per
CDE, and the agreed acceptance standard. If the use was assumed, say so. (Redman customer-supplier model.)

```markdown
## Data pedigree
```
Who, what, when, where, why, how. Sampling and population versus target population. Exclusions and
transformations known. Measurement system. List the questions that could not be answered. (Hoerl and Snee.)

```markdown
## Initial data analysis findings
```
Shape and types; empty, constant and high-cardinality columns; placeholder values found; distribution shapes
(note bimodality and unit mixes); time-ordered volume and missingness; date spikes; correlations between fields
that should agree; outliers and what explains them. (Tate and Halliday; Hoerl statistical thinking.)

```markdown
## Scores by dimension and record-level score
```
A table: completeness, validity/plausibility, accuracy (or "unmeasured"), consistency/concordance,
timeliness/currency, uniqueness, each with the metric, value and the CDEs it covers. Then the perfect-record score,
its interval, the 97% bar and Redman's benchmark distribution. (Redman FAM; Tate six dimensions.)

```markdown
## Error Pareto
```
Error types ranked by count with share and cumulative share; for each of the top three, the likely point of
origin in the creating process. (Redman; Juran.)

```markdown
## Variation and stability
```
Defect rate by unit (site, source, period) with p-chart or funnel limits and the units outside them; trends in
volume, missingness and code mix; incentive or policy breakpoints. State explicitly whether the process looks
stable. (Hoerl; Redman and Hoerl census; Tate practice-level scores.)

```markdown
## Right-data assessment
```
Population match to the decision; coverage gaps; sensitivity of the headline estimate across tiered definitions;
whether an external benchmark exists and whether it is self-referencing. (Hoerl and Redman "right data"; Tate.)

```markdown
## Cost and risk of the defects
```
Apply the rule of ten to the defect rate and the customer's workload; describe the decision risk if the data are
used as-is; note hidden-data-factory effort already being spent. (Redman.)

```markdown
## Root causes and failure pattern
```
For the top Pareto errors, the process step and owner where the error enters. Name the pattern where one fits:
Silent Drift, Proxy Trap, Spreadsheet Cascade, Governance Vacuum, Metric Mirage. (Tate column taxonomy.)

```markdown
## Recommendations
```
Ordered: prevent at source (process and requirement changes, with owners); clean (what, how, with an audit
trail); controls (repeat measurement schedule, p-chart with limits, checkpoints that block downstream flow,
independent QA sample, visibility of error rates next to performance metrics); re-evaluation triggers (new use,
new source, system change). (Redman three modes; Hoerl SPC; Tate checkpoints.)

```markdown
## Limitations and what was not assessed
```
Dimensions not measured and why; pedigree unknowns; sample versus full data; rules that may under-count errors;
anything the reader should verify before relying on the report. (Tate and Halliday transparent reporting.)

```markdown
## Appendix
```
Rules used (the `rules.json`), script command and output locations, FAM worksheet location and instructions for
the human pass, code lists and definitions, data snapshot identifiers.
