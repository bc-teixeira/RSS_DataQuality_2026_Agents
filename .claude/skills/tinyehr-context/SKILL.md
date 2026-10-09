---
name: tinyehr-context
description: Documentation-derived context for TinyEHR v0.2.0 (aliases MIMIC-IV Clinical Database Demo v2.2 derivative, "tinyehr_mimic_format", BIDMC EHR demo, MIMIC-IV demo): purpose and provenance, tables (patients, admissions, transfers, icustays, labevents, chartevents, prescriptions, emar, noteevents), variable definitions, cohort rules, code lists, known limitations and candidate data-quality rules. Use this skill whenever the user asks what a table or variable in TinyEHR or the MIMIC-IV demo means (e.g. admittime, anchor_year, stay_id, charttime vs storetime), which table holds labs, vitals or notes, how tables join, how patients enter the data, which ICD or item codes are used, what the date shifting or generated notes do to the data, or prepares a query or data quality evaluation on /data/raw, even if they do not name this skill.
---

# TinyEHR context

TinyEHR v0.2.0 is a 100-patient, 275-admission, 140-ICU-stay teaching dataset derived from the MIMIC-IV Clinical Database Demo v2.2 (BIDMC, Boston; source period 2008-2019). Three changes were made to the source: dates shifted to 2010s-2020s, ICD codes given decimal points, and 4,580 LLM-generated clinical notes added. Built from documentation in /data on 2026-10-09; no patient-level data was read. Treat the contents as documented intent, not measured quality.

## Where to look
Read `references/Database_Context.md` section by need (open only the section you need):
- Provenance, who/what/when/where/how, access terms: section 1
- Table grain, keys, joins, variable definitions: section 2
- How units enter the data, IDs: section 3
- Code systems and lookup tables: section 4
- Limitations and biases (date shifting, synthetic notes, censored death dates): section 5
- Candidate DQ rules (also `references/rules-seed.json`): section 6
- Literature findings and open questions: sections 7-8

## Rules for using this context
- Cite the section when answering. Where it says `inferred`, `from literature` or "Not documented", say so.
- Never include individual-level rows or real identifiers in answers; this skill holds none.
- For a data quality evaluation, hand section 1 to `data-quality-evaluation` as its pedigree answers and use section 6 as the starting rules file; unresolved items in section 8 go into the report's limitations.
- If the documentation in /data has changed, regenerate with `database-context` rather than editing by hand.
