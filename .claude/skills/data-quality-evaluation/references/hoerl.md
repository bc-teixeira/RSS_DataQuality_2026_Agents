# Roger Hoerl: data pedigree, statistical thinking and the "right data"

Roger W. Hoerl (Union College; formerly GE Global Research), mostly with Ron Snee and more recently with Tom
Redman, supplies the statistician's half of data quality evaluation: understand the process that produced the
data before analysing it, quantify variation, and ask whether the data can answer the question at all.

## 1. Statistical thinking

Hoerl and Snee, *Statistical Thinking: Improving Business Performance* (3rd ed. 2020). Three principles:

1. All work occurs in a system of interconnected processes.
2. Variation exists in all processes.
3. Understanding and reducing variation are the keys to success.

Applied to data: a dataset is the output of a process. Map that process (a SIPOC: suppliers, inputs, process,
outputs, customers) before analysing its output. Variation decomposes into **systematic** (explainable),
**random** and **outliers**. Outliers "may be due to a measurement error, but may also represent legitimate data
points"; they are to be explained, not silently deleted. Plot data in time order and separate common-cause from
special-cause variation before summarising; establish stability before computing capability, averages, or model
fits that assume a stable process.

The 3rd edition added a chapter on data ("Data: The Missing Link") with sections on practical sampling to ensure
data quality, the data pedigree, and the measurement system.

## 2. Data pedigree

Snee and Hoerl, "Inquiry on Pedigree" (*Quality Progress*, Dec 2012); Hoerl and Snee, "Show Me the Pedigree"
(*Quality Progress*, Jan 2019); ISEA *Statistical Engineering Handbook* ch. 2 §3.

Definition: a data pedigree "documents samples, measurement processes utilized, and the subsequent handling of
the data, including any modifications or deletions made, through the present." It covers both the measurement
process and the process that produced the units measured.

Write down before analysis:

- where the data came from and why they were collected;
- how units were selected (sampling frame and scheme; observational or designed);
- the timeframe and whether it is appropriate for the question;
- who collected the data, with what instrument or protocol, and how much judgement was involved;
- every transformation, merge, imputation or deletion since collection.

Pedigree failures to look for explicitly: "biased sampling, inappropriate timeframes for data collection,
inappropriate selection of variables, and poor measurement processes", not only blunders and missing values.
Observational or "found" data deserve closer scrutiny than designed-experiment data. The Challenger O-ring data
are the cautionary example: omitting flights with zero failures destroyed the temperature relationship, so always
ask what records were excluded and why.

## 3. Statistical engineering

Hoerl and Snee, "Statistical Engineering: An Idea Whose Time Has Come?" (*The American Statistician* 71(3),
2017). Five principles: understanding of the problem context; a problem-solving strategy; consideration of the
data pedigree; integration of subject-matter theory; sequential approaches.

Evaluation consequences:

- "An understanding of where the data came from, and specifically how they were collected, are critical to
  determining the value of the data. Many data sets are simply not worth spending a lot of time analyzing."
- Does the sampled population match the population of interest? "Virtually no real data set could be considered
  a true random sample." For a predictive model the population of interest is *future* observations.
- "Current data are not appropriate to answer the question" is a legitimate, and often the most valuable,
  conclusion; the strategy step frequently becomes "obtain better data".
- Work sequentially: collect, analyse, learn, collect better data.
- Deploy with a control plan, including ongoing monitoring of model accuracy.

## 4. Big data does not remove the need for quality

Hoerl, Snee and De Veaux, "Applying statistical thinking to 'Big Data' problems" (*WIREs Comp Stats* 2014);
De Veaux, Hoerl and Snee, "Big Data and the Missing Links" (2016); Snee, De Veaux and Hoerl, "Follow the
Fundamentals" (*Quality Progress* 2014).

Volume does not make "subject-matter models and experiments obsolete, alleviate the need to ensure data quality,
or no longer require that variables accurately measure what they are supposed to." Issues to test for:
**variability or volatility** (inconsistency across time), **veracity** (accuracy and completeness),
**complexity** (linking sources brings missing values, missing variables, measurement variation and definition
conflicts) and **accessibility**. Reconcile variable definitions across sources before modelling. The four
fundamentals: ensure high-quality data; incorporate domain knowledge; develop an overall strategy; use a
sequential approach.

## 5. "Right data" versus "data are right"

Redman and Hoerl, "Data quality and statistics: Perfect together?" (*Quality Engineering* 35(1), 2023); Hoerl
and Redman, MIT SMR Dec 2023; Redman and Hoerl, MIT SMR Apr 2024; Hoerl, "The future of statistics in an AI era"
(*Quality Engineering* 38(3), 2025).

- **Data are right**: accuracy, completeness, consistency of the values.
- **Right data**: the data bear on the specific problem and decision. "Rather than asking 'What can I learn from
  available data?', ask 'What data would be most appropriate to address this specific problem?'" Available data
  "were typically collected for a totally different purpose."
- For AI and ML training sets (MIT SMR 2024): use survey-sampling theory (sampling bias, non-response bias,
  biased questions) to audit the training data; pair the ML model with an interpretable **statistical twin** whose
  goodness-of-fit and uncertainty measures reveal where the right data were not used; run **designed tests** of
  deployed models (grant some credit you would normally deny to learn the false-negative side); monitor deployed
  models with **SPC**, since stability on new data is a basis for inference. Manager questions: does the model
  match domain expectations; could it be simplified; what is your basis for inference? Beware the claim that
  out-of-sample accuracy guarantees accuracy on future data collected under different circumstances.
- Hoerl 2025: "failure to accept and own the challenge of data quality has been the greatest blunder in the
  history of the statistics profession." Data quality is much more than data cleaning; it requires contextual
  and process knowledge and probing questions about data context.

## 6. Measurement systems

DMAIC Measure-phase conventions (Snee and Hoerl Six Sigma books; *Statistical Thinking* ch. 2): write
operational definitions; make a data-collection plan; run a measurement system analysis (repeatability,
reproducibility) before using the data as a baseline; confirm stability before capability. The RWDS
"Data Quality Under the Lens" hypertension column (Hoerl and de Mowbray, June 2026) is the worked example:
device-to-device and tester-to-tester variation, protocol non-compliance, and wrong cuff size producing 39% false
positives and 22% false negatives. Takeaway: never take data at face value; always delve into how, when, where
and by whom they were collected; do not trust a single measurement.

## 7. Hoerl's evaluation checklist

1. Frame the problem and decision first; define fit for use against it (right data) before assessing accuracy.
2. Write the data pedigree: origin, sampling, population vs target population, timeframe, collector, instrument,
   every transformation or deletion.
3. Map the generating process; identify where human judgement, legacy systems or spreadsheets touch the data.
4. Quantify measurement variation before interpreting differences.
5. Plot in time order; separate systematic, random and outlier variation; stability before capability.
6. Run cheap sanity checks early: correlations, clusters, cross-source definition reconciliation, exclusion audits.
7. Explain outliers; do not delete them.
8. Have subject-matter experts vet both data and model; check results against domain knowledge.
9. Work sequentially; be willing to conclude the data cannot answer the question.
10. After deployment, monitor data and model with SPC; make error rates and uncertainty visible beside the KPIs;
    build independent QA.
