# rules.json format for scripts/dq_profile.py

Rules encode the data customer's definition of "error" for each critical data element (CDE). Keep them traceable
to Step 1 of the workflow: every rule should be explainable as "the customer cannot use a record where ...".

```json
{
  "placeholders": ["", "NA", "N/A", "NULL", "null", "None", "-", "?", "UNKNOWN", "9999", "-999", "999"],
  "columns": {
    "patient_id":     {"not_null": true, "unique": true, "regex": "^P\\d{6}$"},
    "sex":            {"allowed": ["F", "M"]},
    "birth_date":     {"type": "date", "min": "1900-01-01", "max": "today"},
    "diagnosis_date": {"type": "date", "min": "1990-01-01", "max": "today"},
    "hba1c_mmol_mol": {"type": "number", "min": 20, "max": 200},
    "bmi":            {"type": "number", "min": 10, "max": 80},
    "dm_type":        {"allowed": ["T1", "T2", "Unspecified", "Proxy"], "flag_values": ["Proxy", "Unspecified"]}
  },
  "cross_field": [
    {"name": "death_not_before_diagnosis",
     "expr": "death_date.isna() | (death_date >= diagnosis_date)"},
    {"name": "type1_has_insulin",
     "expr": "~((dm_type == 'T1') & (insulin_rx == 0))"},
    {"name": "diagnosis_after_birth",
     "expr": "diagnosis_date >= birth_date"}
  ]
}
```

## Column rules

| Key | Meaning |
|---|---|
| `not_null` | Null or placeholder counts as an error (CDEs are treated as `not_null` by default; set `false` to allow blanks) |
| `unique` | Duplicate values count as errors (all but the first occurrence) |
| `allowed` | Value must be in this list (compared as strings, case-sensitive) |
| `flag_values` | Values that are valid but weak (proxy or vague codes); counted separately as "weak", not as errors |
| `regex` | Value must match this regular expression (full match) |
| `type` | `number` or `date`; values that fail to parse count as errors |
| `min`, `max` | Inclusive bounds; for dates, ISO strings or `today` |

## Cross-field rules

`expr` is a pandas expression evaluated with `DataFrame.eval(expr, engine="python")` after date and numeric
columns have been parsed. It must return a boolean Series where **True means the record passes**. Rows where the
expression evaluates to NA are treated as passing (missingness is already counted by the column rules). Each
failing record gets one error attributed to the rule name, which appears in the Pareto alongside column errors.

## Placeholders

Strings in `placeholders` are treated as missing wherever they appear, and additionally reported as "placeholder
values" per column, because Redman and Hoerl both warn that sentinel values masquerading as data are a frequent and
invisible error source. Dates equal to `1900-01-01`, `1970-01-01` or `9999-12-31` are flagged the same way.

## What the rules cannot capture

Rules detect errors someone anticipated. They do not detect a value that is plausible but wrong (accuracy against
reality), a record that should exist but does not (coverage, false negatives), or a dataset that is accurate yet
collected on the wrong population (right data). Report those as unmeasured unless a reference source is available.
