# Template for the generated <dataset-slug>-context/SKILL.md

Replace every `<...>`. Keep it under ~40 lines; the detail belongs in `references/Database_Context.md`.

```markdown
---
name: <dataset-slug>-context
description: Documentation-derived context for <dataset full name and version> (<aliases>): purpose and provenance, tables (<5-8 key table names>), variable definitions, cohort rules, code lists, known limitations and candidate data-quality rules. Use this skill whenever the user asks what a table or variable in <dataset> means, how tables join, how patients/units enter the data, which codes are used, what the limitations or biases are, or prepares a study, query or data quality evaluation on <dataset>, even if they do not name this skill.
---

# <Dataset> context

<Dataset> is <one-line description, period, population, source system>. Built from documentation in /data on <date>;
no patient-level data was read. Treat the contents as documented intent, not measured quality.

## Where to look
Read `references/Database_Context.md` section by need (open only the section you need):
- Provenance, who/what/when/where/how, access terms: section 1
- Table grain, keys, joins, variable definitions: section 2
- How units enter the data, IDs: section 3
- Code systems and lookup tables: section 4
- Limitations and biases: section 5
- Candidate DQ rules (also `references/rules-seed.json`): section 6
- Literature findings and open questions: sections 7-8

## Rules for using this context
- Cite the section when answering. Where it says `inferred`, `from literature` or "Not documented", say so.
- Never include individual-level rows or real identifiers in answers; this skill holds none.
- For a data quality evaluation, hand section 1 to `data-quality-evaluation` as its pedigree answers and use section 6 as the starting rules file; unresolved items in section 8 go into the report's limitations.
- If the documentation in /data has changed, regenerate with `database-context` rather than editing by hand.
```
