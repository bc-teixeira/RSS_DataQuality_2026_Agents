# Database_Context.md template

Use this structure exactly so downstream skills can find sections by heading. Omit nothing: write "Not documented" where
the sources are silent.

```markdown
# Database context: <dataset name and version>

Generated: <date> from <n> documents in /data. Documentation only; no patient-level data was read.

## How to use this file
<3 lines: what it is for, how it feeds data-quality-evaluation, what the tags mean (inferred, from literature)>

## 1. Pedigree and business context
| Question | Answer | Source |
|---|---|---|
| Why was it collected? | | |
| Who recorded it, and with what training/incentive? | | |
| What population does it represent, who is missing? | | |
| Period covered, event vs recording date, lag, refresh cadence | | |
| Sites, systems, vendors, instruments | | |
| How measured/validated; transformations, de-identification, exclusions | | |
| Access, licence, intended and prohibited uses | | |

## 2. Tables and variables
### 2.1 Table overview
| Table | Module/area | Grain (one row per) | Primary key | Purpose |
### 2.2 Join map
| From | To | Keys | Cardinality | Notes |
### 2.3 Variable definitions (one subsection per table)
#### <table>
| Variable | Type | Unit / code system | Allowed values or range | Nullable | Definition and caveats | Source |

## 3. Cohort rules
How units enter the data; ID conventions; inclusion/exclusion; linkage. Concise.

## 4. Code lists and terminologies
| Domain | Code system and version | Lookup table or file | Notes on version changes |

## 5. Known limitations
| # | Limitation | Affects (tables/variables) | Evidence | Source |
Group by: population gaps, definition changes, de-identification effects, missingness, measurement/coding quality.

## 6. DQ rules seed
Hypotheses derived from documentation, for data-quality-evaluation. Not measured quality.
Per table, a rules.json fragment (format: data-quality-evaluation/references/rules-format.md) followed by a source list.

## 7. Literature findings
| Fact | Reference (author, year, PMID/DOI) | Pedigree question it answers |
Include queries run.

## 8. Open questions
Unanswered pedigree questions and critical fields with no definition. State what would answer each.

## Sources
Converted files and papers used, with the inventory of data files that were listed but not opened.
```
