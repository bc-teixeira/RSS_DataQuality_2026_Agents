# Data pedigree interview

Use these questions when the data source is unfamiliar. Ask the user or the documentation; where neither
answers, infer cautiously from the data and label the answer "inferred". Unanswered questions go into the
report's limitations section. The framing follows Hoerl and Snee's data pedigree and the "who, what, when,
where, why, how" provenance standard adopted by the RWDS Data Quality Under the Lens column.

## Why (purpose of collection)

- What was the data originally collected to do? Billing, clinical care, regulatory reporting, marketing,
  operations, research, a survey?
- Were the people recording it paid, measured or incentivised on what they recorded? (Tate: QOF incentives
  changed diabetes coding overnight.)
- Has the purpose changed since? Each new purpose needs a new fitness assessment.

## Who

- Who created each record: a clinician, a clerk, a device, a customer, a model, an ETL job?
- How much judgement did they exercise, and were they trained on the definitions?
- Who has touched the data since (transformations, merges, manual fixes), and is that documented?
- Who owns each critical data element today? If nobody, note "Governance Vacuum".

## What (definitions and population)

- What exactly does each critical field mean? Is there an operational definition, a code list, a unit of measure?
- Did definitions, code systems, units or categories change over the period covered? When?
- What population do the records represent, and how did units enter the dataset? Who is missing (non-responders,
  unlinked records, those who never attended, zero-event units like the Challenger flights)?
- Does the represented population match the population the decision is about, including future cases?

## When

- What time period is covered, and is it appropriate for the question?
- Is the event date the recording date? How long is the typical lag (currency)?
- Are there batch loads, retrospective entry or migrations that create date spikes?
- How current is the extract, and how often is it refreshed?

## Where

- Which systems, sites, vendors, countries or instruments did the data come from?
- Do sites differ in protocol, software, coding practice or completeness? (Variation across units, not the
  average, often decides fitness.)
- Where did the data pass through spreadsheets, email, manual re-keying or legacy systems?

## How (measurement system and handling)

- What instrument or protocol produced each measured value? Is its repeatability and reproducibility known?
- Were values validated at entry (drop-downs, range checks) or free-typed?
- What has been excluded, imputed, deduplicated, truncated, recoded or re-labelled between collection and this
  extract? Is the raw extract available?
- Is there any independent reference (gold standard, linked source, free text, physical recount) against which
  accuracy can be checked, or is accuracy unmeasurable here?

## Closing questions

- What does the data customer consider an error in each critical field?
- What quality standard does the decision require (Redman's loosest bar is 97% perfect records)?
- What would make you conclude the data cannot answer the question, and what data could?
