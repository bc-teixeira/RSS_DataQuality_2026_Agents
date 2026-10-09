---
name: database-context
description: Generate a dataset-specific context skill (containing a single Database_Context.md) from the documentation in the /data folder (PDF, Word, Excel, Markdown), covering pedigree and business context, table and variable definitions, cohort rules, code lists and known limitations, plus a seed of data-quality rules. Use this skill whenever the user wants to document, summarise, onboard to or "get context on" a database, dataset, EHR, registry or claims source, asks what the tables and variables mean, wants a data dictionary or schema overview, needs the pedigree answers before a data quality evaluation, or says things like "read the docs in /data", "what do we know about this dataset", "prepare context for the data-quality-evaluation skill". Use it even when the user does not mention Database_Context.md. Works from documentation only, with no database connection and no patient-level data.
---

# database-context

Turn whatever documentation sits in `/data` into a new skill (`<dataset>-context`) whose reference is one structured file, `Database_Context.md`, that a person or another skill (notably `data-quality-evaluation`) can read instead of re-reading dozens of source documents. The file answers the pedigree questions that `data-quality-evaluation` asks about an unfamiliar source (see its `references/pedigree-questions.md`), so a good context file lets that skill skip the interview and go straight to rules and profiling.

## Ground rules

- **Documentation only.** There is no database connector. Everything comes from files in `/data`. Never open tabular data files (CSV, parquet, SAS, Stata, etc.) to read rows: they may contain patient-level data, and the context document must not expose any. The converter script lists them by name and size only. If a documentation-style spreadsheet turns out to contain individual-level rows, stop using it and say so in the limitations.
- **No patient-level content in the output**, including example rows, real identifiers, or dates tied to individuals. Use the documentation's own illustrative values or invented placeholders, labelled as such.
- **Every claim needs a source.** Cite the converted file or paper (`[source: modules/hosp/patients.md]`). Tag anything not stated by the documents as `inferred` or `from literature`. An unanswered question is a finding, not something to fill with plausible text: put it under "Open questions".
- **Do not invent definitions.** If two documents disagree, report both and the version/date of each.

## Workflow

### 1. Inventory and convert

Run the converter. The layout can be flat or nested; the script scans `/data` recursively.

```bash
python <skill-path>/scripts/convert_docs.py data data/_converted
```

It writes one `.md` per documentation file plus `_inventory.md` (converted, failed, data files skipped). It uses `pypdf`, `python-docx` and `openpyxl` when installed. If a converter is missing or a PDF is scanned, tell the user what was skipped and ask whether to install it or supply another format; do not silently drop a source. PDF tables lose structure in extraction, so verify table-heavy PDF content before copying it.

Read `_inventory.md` first, then decide the reading order: overview/README and "about" documents, then schema overview, then per-table pages, then glossary/changelog, then papers. For a large corpus (dozens of table pages) delegate per-table extraction to subagents in parallel, one batch of tables each, with the section template from `references/context-template.md`, and merge the results yourself.

### 2. Extract

Work through the sources and collect, with citations:

1. **Pedigree and business context** (highest priority). Answer the six pedigree questions: why collected, who recorded it, what population and definitions, when (period, lag, refresh), where (sites, systems), how (instruments, validation, transformations, de-identification). Include licence/access conditions and the intended use.
2. **Tables and variables** (highest priority). Per table: purpose, grain (one row per what), primary key, foreign keys and join paths, then per variable: name, type, unit, allowed values or code system, nullability, and any documented caveat. Keep it as tables, not prose.
3. **Known limitations and DQ rules seed** (highest priority). Documented caveats, changelog items that changed definitions, de-identification effects (shifted dates, masked free text), missingness patterns, and population gaps. Then convert the checkable ones into candidate rules (below).
4. **Cohort rules** (shorter treatment). How units enter the dataset (inclusion/exclusion, linkage, ID conventions, what a "patient", "admission" or "stay" is).
5. **Code lists and terminologies** (shorter treatment). Which code systems appear where (e.g. ICD version, local item IDs), where the lookup tables live, and version changes. Record where the list is, not every code, unless a list is short and clinically central.

### 3. Close gaps with a literature search

After extraction, list the pedigree questions and critical fields still unanswered. Search only for those gaps; do not search to re-confirm what the documents already say.

Use PubMed (the PubMed tools, if available; otherwise web search) for the dataset's primary description paper, validation studies, and papers reporting its known biases or coding quality. Typical queries: `"<dataset name>" validation`, `"<dataset name>" data quality OR limitations OR bias`, and the dataset's version name. Prefer the dataset's own publication and peer-reviewed validations over commentary. Preprints are acceptable only if tagged as such.

Rules for what enters the file:
- One line per fact, tagged `from literature`, with author, year and PMID or DOI.
- Do not paste abstracts or text beyond a short paraphrase.
- If nothing relevant is found, record that in "Open questions" with the queries tried.
- Local papers already in `/data` count as documentation, not literature search; cite them as sources.

### 4. Synthesise and package as a skill

The deliverable is a new skill that carries the dataset knowledge, so any later session loads it automatically when the dataset comes up. Create it at `.claude/skills/<dataset-slug>-context/` (slug from the dataset name, lowercase, hyphenated, e.g. `mimic-iv-context`; confirm the name with the user if the dataset has several plausible names):

```
<dataset-slug>-context/
├── SKILL.md                      generated from references/generated-skill-template.md
└── references/
    ├── Database_Context.md       the single synthesised file (references/context-template.md)
    └── rules-seed.json           optional: the section 6 rules as one valid rules.json
```

Fill `references/context-template.md` for `Database_Context.md`. Keep the three priority sections (pedigree, tables/variables, limitations and rules seed) complete and detailed, and the cohort and code-list sections concise. Put a short "How to use this file" and a source list at the top and bottom.

Fill `references/generated-skill-template.md` for the generated `SKILL.md`. Its description must name the dataset, its aliases and the tables, so the skill triggers on questions like "what does `admittime` mean" or "which table has lab results" without the user naming the skill. Keep its body short: the dataset in three lines, which sections of `Database_Context.md` to read for which question, the no-patient-level-data rule, and the instruction to feed the file into `data-quality-evaluation` as its pedigree input. Do not duplicate the context in the SKILL.md; the detail lives in the reference file so it loads only when needed. If `Database_Context.md` exceeds roughly 300 lines, give it a table of contents.

Do not copy converted source files into the generated skill; they can contain licence-restricted text and bulk. Cite their original paths instead. Do not overwrite an existing `<dataset-slug>-context` skill without showing the user what changes.

**DQ rules seed.** Emit candidate rules in the format of `data-quality-evaluation/references/rules-format.md` (a `rules.json` fragment per table: `not_null`, `unique`, `allowed`, `regex`, `type`, `min`, `max`, and `cross_field` expressions). Only write a rule when a document supports it (for example "`dischtime` is after `admittime`", an allowed-values list, a documented key). Mark each rule with its source. Rules are hypotheses about the data's meaning, not measured quality; say so.

### 5. Check before handing over

- Every table in the schema overview has a section, or is listed under "Not documented".
- Every cross-table join named in the docs appears in the join map.
- No example row, real-looking identifier, or individual date appears anywhere.
- Every `from literature` or `inferred` fact is tagged; every other fact has a source path.
- Open questions list matches the unanswered pedigree questions.

- The generated `SKILL.md` has valid frontmatter (`name` matches the folder, description names the dataset) and points to `references/Database_Context.md`.

Finish by telling the user: the path of the generated skill, which sources were converted or skipped, which pedigree questions remain open, and how many rules were seeded. Offer to run `data-quality-evaluation` with this file as its pedigree input.
