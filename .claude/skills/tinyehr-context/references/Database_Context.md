# Database context: TinyEHR v0.2.0 (MIMIC format; derived from MIMIC-IV Clinical Database Demo v2.2)

Generated: 2026-10-09 from 58 converted documents in /data (plus 34 data files listed by name and size only). Documentation only; no patient-level data was read.

## How to use this file
Single reference for what TinyEHR contains and what it means, so `data-quality-evaluation` can take section 1 as its pedigree answers and section 6 as its starting rules. Tags: `inferred` = not stated by a document, deduced; `from literature` = external paper (section 7). "Not documented" = sources are silent (see section 8).
Source shorthand (paths under /data/documentation): **ABOUT** = tinyehr/ABOUT_THE_DATA.md; **README** = tinyehr/README.md; **PAPER** = mimic_iv_paper/Johnson_2023_MIMIC-IV_Scientific_Data.pdf; **DEMO** = physionet_mimic_iv_demo_v2.2/README.txt; **MIMIC:`x`** = mimic_iv_official_docs/iv/`x` (e.g. MIMIC:modules/hosp/patients.md); **MANIFEST** = /data/manifest_00_get_the_data.csv.
Important: the MIMIC-IV official docs describe the full MIMIC-IV v2.2 (~300k patients). TinyEHR is a 100-patient subset with three documented changes, so statements about row counts, coverage periods and the ED/CXR/ECG modules from those docs do not apply to it unless ABOUT says so.

## Contents
1 Pedigree · 2 Tables and variables · 3 Cohort rules · 4 Code lists · 5 Limitations · 6 DQ rules seed · 7 Literature · 8 Open questions · Sources

## 1. Pedigree and business context
| Question | Answer | Source |
|---|---|---|
| Why was it collected? | Underlying data: routine clinical care, provider orders, monitoring and billing at BIDMC; "not explicitly for retrospective analysis". MIMIC-IV was published to support research and education. TinyEHR was built for learning, prototyping and agentic-AI experiments, not clinical analysis ("should not be used for clinical analysis, medical decision-making, or patient care"). | PAPER (Background, Methods); MIMIC:about/concepts.md; README (caution box) |
| Who recorded it, and with what training/incentive? | Hospital staff in routine care: nurses chart ICU observations and validate them (`storetime`); bedside staff scan barcodes in eMAR; providers enter orders (POE); trained coders assign ICD diagnoses after reading signed notes, with "few incentives" to rank `seq_num` perfectly; billing staff assign DRG/HCPCS. Notes in TinyEHR were written by an LLM (Claude Opus 4.6), not clinicians. | MIMIC:modules/hosp/diagnoses_icd.md; MIMIC:modules/hosp/emar.md; PAPER (Billing); ABOUT §3 |
| What population does it represent, who is missing? | Source MIMIC-IV: adults (≥18 at first visit) admitted to the ED or an ICU at BIDMC 2008-2019, excluding people on an enhanced-protection list; neonates removed (v2.0); a test-set subset of subject_ids held out (v2.1). Demo: 100 patients chosen as a subset (selection method Not documented). Single US academic centre; not representative of any population. Out-of-hospital deaths are visible only up to 1 year after discharge. | PAPER (Clinical cohort); MIMIC:about/changelog.md; DEMO; README (Known Limitations); MIMIC:modules/hosp/patients.md |
| Period covered, event vs recording date, lag, refresh cadence | Source years 2008-2019. TinyEHR dates are shifted per patient to "realistic but fictional" years in the 2010s-2020s, chosen at random within each patient's `anchor_year_group`; so calendar dates are not true dates and the real year is known only to a 3-year band. Event time = `charttime` (hour-block, may precede actual measurement); recording time = `storetime`. Lab `charttime` is usually specimen collection, well before result availability (`storetime`). eMAR present only after rollout (see limitation L10). No refresh cadence: static snapshot; manifest retrieval 2026-10-08, upstream commit `442e8dfd…` (data files) and `81822278…` (docs). | ABOUT §1; MIMIC:about/concepts.md; MIMIC:modules/hosp/labevents.md; MANIFEST |
| Sites, systems, vendors, instruments | BIDMC hospital-wide EHR (SQL Server warehouse) for `hosp`; MetaVision (iMDsoft) ICU information system for `icu`; Online Medical Record (OMR) for outpatient measurements; eMAR barcode system for administrations. Some items are duplicated between systems (e.g. labs synced into chartevents). Pipeline: PostgreSQL at MIT, CSV export. TinyEHR layer: Python build scripts, Parquet on HuggingFace, PyPI package `tinyehr`. | PAPER (Acquisition); MIMIC:modules/icu/index.md; MIMIC:modules/hosp/omr.md; README |
| How measured/validated; transformations, de-identification, exclusions | MIMIC build: single reproducible SQL build; integrity, consistency (e.g. ≥99% of ICU hadm_id have a billed diagnosis; ≥99% of ICU stays have a heart rate) and de-identification unit tests. De-identification: HIPAA Safe Harbor with custom algorithms, random subject_id/hadm_id, patient-level date shift, PHI in free text replaced with `___`, ages >89 capped. TinyEHR changes: (1) per-patient date shift (offsets saved in raw/metadata/date_offsets.csv); (2) ICD decimal formatting; (3) 4,580 LLM-generated notes (not clinician-validated). All other values "identical to the original MIMIC-IV Demo". | PAPER (Technical Validation, Deidentification); ABOUT |
| Access, licence, intended and prohibited uses | TinyEHR: ODbL-1.0, no credentialing or DUA; derived versions must use the same licence; citation required (README BibTeX 2026). Parent MIMIC-IV demo also ODbL (PhysioNet). Full MIMIC-IV needs credentialing and DUA (no re-identification, no sharing). Intended: learning, prototyping, agent development. Not for clinical use or population inference. | README; DEMO; physionet_mimic_iv_demo_v2.2/LICENSE.txt; tinyehr/LICENSE; PAPER (Access) |

## 2. Tables and variables
Scope: MIMIC format only (the data in /data/raw/tinyehr_mimic_format). The OMOP format (23 tables) is described in ABOUT but its files are not in /data/raw. Types are the Postgres types documented upstream; TinyEHR ships CSV/Parquet, so storage types may differ (codes are strings; large IDs stay integers) [ABOUT, Design Decisions]. Row counts from ABOUT.

### 2.1 Table overview
| Table | Module | Grain (one row per) | Primary key | Rows | Purpose |
|---|---|---|---|---|---|
| patients | hosp | patient | subject_id | 100 | Static demographics, anchor year/age, date of death |
| admissions | hosp | hospital admission | hadm_id | 275 | Admission/discharge times, type, locations, insurance, race |
| transfers | hosp | physical location stay (ED, ward, ICU) | transfer_id (subject_id+transfer_id inferred) | 1,190 | Patient movement; source of icustays |
| services | hosp | service change within admission | none documented (subject_id, hadm_id, transfertime inferred) | 319 | Clinical service responsible |
| diagnoses_icd | hosp | billed diagnosis per admission | (hadm_id, seq_num) inferred | 4,506 | ICD-9/10 billing diagnoses |
| procedures_icd | hosp | billed procedure per admission | (hadm_id, seq_num) inferred | 722 | ICD-9/10 hospital-billed procedures |
| drgcodes | hosp | DRG assignment per admission | none documented | 454 | DRG for reimbursement |
| hcpcsevents | hosp | HCPCS code per admission | (hadm_id, seq_num) inferred | 61 | Hospital-billed HCPCS/CPT events |
| labevents | hosp | lab result | labevent_id | 107,727 | Lab measurements, whole hospital stay and outpatient |
| microbiologyevents | hosp | specimen×test×organism×antibiotic result | microevent_id | 2,899 | Cultures and sensitivities |
| prescriptions | hosp | prescribed drug component | none documented (pharmacy_id + drug_type/drug inferred) | 18,087 | Prescribed medications |
| pharmacy | hosp | pharmacy order | pharmacy_id | 15,306 | Dispensing detail for prescriptions |
| emar | hosp | medication administration event | emar_id | 35,835 | Barcode-scanned administrations |
| emar_detail | hosp | formulary dose line of an administration | (emar_id, parent_field_ordinal) inferred | 72,018 | Dose/product detail for emar |
| poe | hosp | provider order | poe_id | 45,154 | Orders (all types) |
| poe_detail | hosp | order attribute (EAV) | (poe_id, field_name) inferred | 3,795 | Order attributes |
| omr | hosp | outpatient/inpatient observation | (subject_id, chartdate, seq_num, result_name) inferred | 2,964 | BP, height, weight, BMI, eGFR |
| provider | hosp | provider | provider_id | 40,508 | List of provider ids |
| d_labitems | hosp | lab concept | itemid | 1,622 | Lab dictionary |
| d_icd_diagnoses | hosp | ICD diagnosis code+version | (icd_code, icd_version) | 109,775 | Diagnosis dictionary |
| d_icd_procedures | hosp | ICD procedure code+version | (icd_code, icd_version) | 85,257 | Procedure dictionary |
| d_hcpcs | hosp | HCPCS code | code | 89,200 | HCPCS dictionary |
| icustays | icu | ICU stay | stay_id | 140 | ICU stay definitions |
| chartevents | icu | charted observation | none documented | 668,862 | Vitals, settings, assessments |
| datetimeevents | icu | charted date-valued observation | none documented | 15,280 | Date-valued items |
| inputevents | icu | infusion/bolus row | none documented (orderid linkage) | 20,404 | IV inputs |
| ingredientevents | icu | ingredient of an input | none documented | 25,728 | Water/nutrition content of inputs |
| outputevents | icu | output event | none documented | 9,362 | Urine, drains |
| procedureevents | icu | ICU procedure | none documented | 1,468 | Ventilation, lines, etc. |
| d_items | icu | ICU concept | itemid | 4,014 | ICU dictionary |
| caregiver | icu | caregiver | caregiver_id | 15,468 | List of ICU caregiver ids |
| noteevents | notes | generated clinical note | note_id | 4,580 | LLM-generated notes (14 types); replaces MIMIC-IV-Note discharge/radiology tables |
| date_offsets (raw/metadata) | metadata | patient `inferred` | subject_id `inferred` | Not documented | Per-patient date-shift offsets; counted as the 33rd "table" in ABOUT (§8 Q12) |

### 2.2 Join map
| From | To | Keys | Cardinality | Notes |
|---|---|---|---|---|
| admissions, transfers, services | patients | subject_id | many→1 | MIMIC:modules/hosp/{admissions,transfers,services}.md |
| transfers, services, all hadm-level tables | admissions | hadm_id | many→1 | transfers.hadm_id nullable (ED visits without admission) |
| icustays | admissions / patients | hadm_id / subject_id | many→1 | icustays derived from transfers |
| icustays.stay_id | transfers.transfer_id | stay_id equals first transfer_id of the stay "often identical" | 1→many ward rows | stay_id is generated, not source-based |
| chartevents, datetimeevents, inputevents, outputevents, procedureevents, ingredientevents | icustays | stay_id | many→1 | MIMIC:modules/icu/index.md |
| icu event tables | d_items | itemid | many→1 | each itemid used in only one event table (`linksto`) |
| labevents | d_labitems | itemid | many→1 | |
| diagnoses_icd | d_icd_diagnoses | icd_code + icd_version | many→1 | all codes documented as present in dictionary (v1.0) |
| procedures_icd | d_icd_procedures | icd_code + icd_version | many→1 | |
| hcpcsevents.hcpcs_cd | d_hcpcs.code | | many→1 | licensing: not all definitions available |
| prescriptions / emar / pharmacy | each other | pharmacy_id | pharmacy 1→many | emar_detail rarely has several pharmacy_id per emar_id |
| prescriptions, emar, pharmacy | poe | poe_id | many→1 | |
| poe_detail | poe | poe_id | many→1 (EAV) | |
| emar_detail | emar | emar_id | many→1 | one NULL-ordinal row (dose due) + rows 1.1…1.N per formulary dose |
| poe.discontinue_of_poe_id / discontinued_by_poe_id | poe.poe_id | | self-join | |
| admissions.admit_provider_id; labevents/microbiologyevents/poe/prescriptions.order_provider_id; emar.enter_provider_id | provider | provider_id | many→1 | |
| icu event tables.caregiver_id | caregiver | caregiver_id | many→1 | |
| noteevents | patients / admissions | subject_id / hadm_id | many→1 | `inferred` from column list (ABOUT §3) |
| labevents ↔ chartevents | n/a | duplicated items | | chartevents copies of labs; labevents is "ground truth" on disagreement |

### 2.3 Variable definitions
Nullable follows the upstream NOT NULL declarations; "not stated" means the docs give no nullability. Common identifiers: `subject_id` = individual patient (unique per patient; INTEGER); `hadm_id` = one hospitalization (INTEGER, unique per admission); `stay_id` = contiguous department stay (INTEGER); `provider_id` = "P" + 3 digits/letters pattern, random, VARCHAR(10); `caregiver_id` = ICU documenter, random integer [MIMIC:_includes/*.md]. Columns ending `time` have minute resolution; `date` columns day resolution with 00:00:00 meaning unknown time, not midnight [MIMIC:about/concepts.md].

#### patients
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id | INTEGER | id | unique | No | Primary key | MIMIC:modules/hosp/patients.md |
| gender | VARCHAR(1) | | values not listed (F shown in README illustrations) | No | "genotypical sex" | same |
| anchor_age | INTEGER | years | >89 at anchor year is set to 91 | No | Age in `anchor_year`. Concepts page says 300 for >89 (conflict, L6) | patients.md; concepts.md |
| anchor_year | INTEGER | year | Shifted year | No | Original MIMIC value in 2100+; TinyEHR README shows realistic years, but ABOUT lists only `dod` as modified for patients (conflict, §8) | patients.md; ABOUT; README |
| anchor_year_group | VARCHAR(255) | 3-year range "YYYY - YYYY" | | No | True year range containing `anchor_year`; unchanged by TinyEHR | patients.md; ABOUT |
| dod | TIMESTAMP(0) | date | | Yes | Date of death from hospital or Massachusetts vital records; out-of-hospital deaths captured only up to 1 year after discharge, later deaths censored, so NULL ≠ alive beyond 1 year. Shifted by TinyEHR | patients.md; PAPER; ABOUT |

#### admissions
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id | INTEGER | | FK patients | No | | MIMIC:modules/hosp/admissions.md |
| hadm_id | INTEGER | | 2000000-2999999 (upstream) | No | Primary key | same |
| admittime | TIMESTAMP | | | No | From ADT system | same |
| dischtime | TIMESTAMP | | | Yes | | same |
| deathtime | TIMESTAMP | | | Yes | Only for in-hospital death; almost always equals dischtime, typographical discrepancies possible | same |
| admission_type | VARCHAR(40) | | 9 values: AMBULATORY OBSERVATION, DIRECT EMER., DIRECT OBSERVATION, ELECTIVE, EU OBSERVATION, EW EMER., OBSERVATION ADMIT, SURGICAL SAME DAY ADMISSION, URGENT | No | Urgency class | same |
| admit_provider_id | VARCHAR(10) | provider_id | FK provider | Yes | Added v2.2 | same; MIMIC:about/changelog.md |
| admission_location | VARCHAR(60) | text | e.g. PHYSICIAN REFERRAL, EMERGENCY ROOM, TRANSFER FROM HOSPITAL (full list Not documented) | Yes | Location before arrival; maps loosely to UB-04 codes; several internal codes may be merged | same |
| discharge_location | VARCHAR(60) | text | e.g. HOME, DIED, SKILLED NURSING FACILITY, REHAB | Yes | Disposition | same |
| insurance | VARCHAR(255) | | not listed | Yes | Per admission, may change between stays | same |
| language | VARCHAR(10) | | not listed | Yes | Per admission | same |
| marital_status | VARCHAR(30) | | not listed | Yes | Per admission | same |
| race | VARCHAR(80) | | not listed | Yes | Doc heading says `ethnicity` but column is `race` (naming inconsistency); race categories were aggregated during de-identification | same; PAPER (checks) |
| edregtime, edouttime | TIMESTAMP | | | Yes | ED registration/discharge; v2.0 fixed missing values for ED-admitted stays | same; changelog |
| hospital_expire_flag | SMALLINT | | 0, 1 | Yes | 1 = died in hospital | same |
Caveat: organ-donor accounts appear as separate admissions with very short or negative LOS and `deathtime` duplicating the earlier admission's.

#### transfers
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id | INTEGER | | | No | | MIMIC:modules/hosp/transfers.md |
| hadm_id | INTEGER | | | Yes | NULL for ED stays with no admission | same; changelog v2.0 |
| transfer_id | INTEGER | | | No | Generated, one per physical location stay; regenerated in v1.0 (not compatible with earlier versions) | same |
| eventtype | VARCHAR(10) | | ed, admit, transfer, discharge | Yes | | same |
| careunit | VARCHAR(255) | text | unit list Not documented; abbreviation list (MICU, SICU, CCU, CVICU, NICU) in glossary | Yes | Ward/unit type | same; MIMIC:about/glossary |
| intime, outtime | TIMESTAMP(0) | | | Yes | Entry/exit of unit | same |

#### services
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id | INT | | FK | not stated | | MIMIC:modules/hosp/services.md |
| transfertime | TIMESTAMP(0) | | | not stated | Time of service change | same |
| prev_service, curr_service | VARCHAR(20) | service code | CMED, CSURG, DENT, ENT, EYE, GU, GYN, MED, NB, NBB, NMED, NSURG, OBS, ORTHO, OMED, PSURG, PSYCH, SURG, TRAUM, TSURG, VSURG | prev may be null | Service is not physical location; use for e.g. surgical patients. NB/NBB are newborn although neonates were removed upstream (see §8) | same; changelog v2.0 |

#### diagnoses_icd
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id | INTEGER | | FK | No | | MIMIC:modules/hosp/diagnoses_icd.md |
| seq_num | INTEGER | rank | max 39 per admission (PAPER) | No | Billing priority, not reliable importance ranking; sepsis forced to 2nd place | same; PAPER |
| icd_code | VARCHAR(7) | ICD-9-CM / ICD-10-CM | TinyEHR inserts decimal after 3rd char | Yes | Upstream codes had no decimal; TinyEHR format differs from upstream and from OMOP | same; ABOUT §2 |
| icd_version | INTEGER | | 9, 10 | Yes | | same |

#### procedures_icd
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id | INTEGER | | FK | No | | MIMIC:modules/hosp/procedures_icd.md |
| seq_num | INTEGER | | | No | Priority; date does not strictly follow it | same |
| chartdate | DATE | | | No | Procedure date (shifted) | same |
| icd_code | VARCHAR(7) | ICD-9-CM proc (decimal after 2nd digit), ICD-10-PCS (no decimal) | | Yes | Hospital-billed procedures only, not provider-billed | same; ABOUT §2 |
| icd_version | INTEGER | | 9, 10 | Yes | | same |

#### drgcodes
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id | INTEGER | | FK | Yes (not NOT NULL) | | MIMIC:modules/hosp/drgcodes.md |
| drg_type | VARCHAR(4) | ontology | AP-DRG and MS-DRG (PAPER) | Yes | Which DRG system | same; PAPER |
| drg_code | VARCHAR(10) | DRG | | Yes | | same |
| description | VARCHAR(195) | text | | Yes | | same |
| drg_severity, drg_mortality | SMALLINT | | scale not stated | Yes | Only for ontologies that define them | same |

#### hcpcsevents
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id | INTEGER | | FK | No | | MIMIC:modules/hosp/hcpcsevents.md |
| chartdate | DATE | | | Yes | Added v1.0, "every row is associated with a date" | same; changelog |
| hcpcs_cd | CHAR(5) | HCPCS/CPT | | No | FK to d_hcpcs.code | same |
| seq_num | INTEGER | | | No | Order within admission, not guaranteed priority | same |
| short_description | VARCHAR(180) | text | | Yes | | same |

#### labevents
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| labevent_id | INTEGER | | unique | No | | MIMIC:modules/hosp/labevents.md |
| subject_id | INTEGER | | | No | | same |
| hadm_id | INTEGER | | | Yes | Assigned only if lab falls inside a transfers row or has an ED stay; ~98% of labs that could be assigned by time are (v2.1); use time joins to admissions | same |
| specimen_id | INTEGER | | | No | Groups results from one specimen | same |
| itemid | INTEGER | d_labitems | | No | | same |
| order_provider_id | VARCHAR(10) | | | Yes | v2.2 | same |
| charttime | TIMESTAMP(0) | | | Yes | Usually specimen collection time; much earlier than availability | same |
| storetime | TIMESTAMP(0) | | ≥ charttime expected | Yes | When result was available | same |
| value | VARCHAR(200) | | | Yes | Some values were in `comments` before v2.0 | same; changelog |
| valuenum | DOUBLE | | numeric cast of value | Yes | | same |
| valueuom | VARCHAR(20) | unit | | Yes | | same |
| ref_range_lower, ref_range_upper | DOUBLE | lab unit | | Yes | Normal range | same |
| flag | VARCHAR(10) | | values not listed | Yes | Mainly "abnormal" | same |
| priority | VARCHAR(7) | | ROUTINE / STAT | Yes | | same |
| comments | TEXT | free text | `___` = fully scrubbed; NULL = no comment | Yes | De-identified | same |

#### microbiologyevents
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| microevent_id | INTEGER | | unique | No | | MIMIC:modules/hosp/microbiologyevents.md |
| subject_id | INTEGER | | | No | | same |
| hadm_id | INTEGER | | | Yes | ~96% of assignable (v2.1) | same |
| micro_specimen_id | INTEGER | | | No | Regenerated in v0.4 | same; changelog |
| order_provider_id | VARCHAR(10) | | | Yes | | same |
| chartdate / charttime | TIMESTAMP(0) | | | chartdate No; charttime Yes | chartdate = charttime truncated; charttime NULL when time unknown | same |
| spec_itemid, spec_type_desc | INTEGER, VARCHAR(100) | | | No | Specimen | same |
| test_seq | INTEGER | | | No | Distinguishes bottles/samples | same |
| storedate, storetime | TIMESTAMP(0) | | | Yes | Time of last known update (final result) | same |
| test_itemid, test_name | INTEGER, VARCHAR(100) | | | Yes | | same |
| org_itemid, org_name | INTEGER, VARCHAR(100) | | | Yes | NULL = no growth, except itemid 90856 which is "NEGATIVE" | same |
| isolate_num | SMALLINT | | starts at 1 | Yes | | same |
| quantity | VARCHAR(50) | | | Yes | | same |
| ab_itemid, ab_name | INTEGER, VARCHAR(30) | | | Yes | Antibiotic tested | same |
| dilution_text, dilution_comparison, dilution_value | VARCHAR(10), VARCHAR(20), DOUBLE | | | Yes | | same |
| interpretation | VARCHAR(5) | | S, R, I, P | Yes | Sensitivity | same |
| comments | TEXT | | `___` = scrubbed | Yes | Sometimes holds the result itself | same |

#### prescriptions
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id, pharmacy_id | INTEGER | | | No | pharmacy_id links to pharmacy/emar | MIMIC:modules/hosp/prescriptions.md |
| poe_id, poe_seq | VARCHAR(25), INTEGER | | | Yes | Link to poe | same |
| order_provider_id | VARCHAR(10) | | | Yes | | same |
| starttime, stoptime | TIMESTAMP(3) | | | Yes | Prescribed times, not guaranteed administration; a handful lack hour (internal assessment of full MIMIC) | same; MIMIC:about/whatsnew.md |
| drug_type | VARCHAR(20) | | MAIN, BASE, ADDITIVE | No | | same |
| drug | VARCHAR(255) | free text | | No | Displayed EHR name | same |
| formulary_drug_cd | VARCHAR(50) | hospital ontology | | Yes | Same value set as emar_detail.product_code | same; changelog v2.0 |
| gsn, ndc | VARCHAR | GSN; NDC (11-digit string, keep leading zeros) | | Yes | | same; ABOUT |
| prod_strength, form_rx, dose_val_rx, dose_unit_rx, form_val_disp, form_unit_disp | VARCHAR | text/units | | Yes | Dose fields are strings | same |
| doses_per_24_hrs | REAL | | | Yes | | same |
| route | VARCHAR(50) | | | Yes | | same |

#### pharmacy
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id, pharmacy_id | INTEGER | | pharmacy_id unique | No | | MIMIC:modules/hosp/pharmacy.md |
| poe_id | VARCHAR(25) | | | Yes | | same |
| starttime, stoptime | TIMESTAMP(3) | | | Yes | | same |
| medication | TEXT | | | Yes | | same |
| proc_type | VARCHAR(50) | | e.g. IV Piggyback, Non-formulary, Unit Dose | No | | same |
| status | VARCHAR(50) | | active, inactive, discontinued | Yes | | same |
| entertime | TIMESTAMP(3) | | | No | | same |
| verifiedtime | TIMESTAMP(3) | | | Yes | | same |
| route, frequency, disp_sched | VARCHAR | | frequency shorthand e.g. Q6H | Yes | | same |
| infusion_type | VARCHAR(15) | | B, C, N, N1, O, R | Yes | | same |
| sliding_scale | VARCHAR(1) | | Y, N | Yes | | same |
| lockout_interval, basal_rate, one_hr_max, doses_per_24_hrs, duration, duration_interval, expiration_value, expiration_unit, expirationdate, dispensation, fill_quantity | mixed | | | Yes | doses_per_24_hrs misleading for continuous infusions | same |

#### emar
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id | INTEGER | | | No | | MIMIC:modules/hosp/emar.md |
| hadm_id | INTEGER | | | Yes | v2.2 imputed ~2.5% previously missing; such rows fall outside admission/discharge times | same; changelog v2.2 |
| emar_id | VARCHAR(25) | "subject_id-emar_seq" | unique | No | Primary key | same |
| emar_seq | INTEGER | | consecutive | No | | same |
| poe_id | VARCHAR(25) | | | No | | same |
| pharmacy_id | INTEGER | | | Yes | | same |
| enter_provider_id | VARCHAR(10) | | | Yes | | same |
| charttime | TIMESTAMP | | | No | Administration time | same |
| medication | TEXT | | | Yes | | same |
| event_txt | VARCHAR(100) | | Administered, Applied, Confirmed, Delayed, Not Given, … | Yes | Not every row is an administration | same |
| scheduletime | TIMESTAMP | | | Yes | | same |
| storetime | TIMESTAMP | | ≥ charttime expected | No | | same |

#### emar_detail
Columns: subject_id, emar_id, emar_seq (not null); parent_field_ordinal (NULL for the dose-due row, '1.1'…'1.N' for formulary doses); administration_type (e.g. IV Bolus, IV Infusion); pharmacy_id; barcode_type; reason_for_no_barcode; complete_dose_not_given; dose_due(+_unit); dose_given(+_unit); will_remainder_of_dose_be_given; product_amount_given, product_unit, product_code, product_description, product_description_other; prior_infusion_rate, infusion_rate, infusion_rate_adjustment, infusion_rate_adjustment_amount, infusion_rate_unit; route; infusion_complete; completion_interval; new_iv_bag_hung; continued_infusion_in_other_location; restart_interval; side; site; non_formulary_visual_verification. All dose/rate fields are VARCHAR (strings), all nullable except the three identifiers. Whole-administration fields (dose_due) appear only on the NULL-ordinal row; per-dose fields only on ordinal rows. [MIMIC:modules/hosp/emar_detail.md; PAPER (Medication)]

#### poe / poe_detail
- poe: poe_id VARCHAR(25) "subject_id-poe_seq" (PK), poe_seq, subject_id, hadm_id (nullable), ordertime (not null), order_type (16 values: ADT orders, Blood Bank, Cardiology, Consults, Critical Care, General Care, Hemodialysis, IV therapy, Lab, Medications, Neurology, Nutrition, OB, Radiology, Respiratory, TPN), order_subtype, transaction_type (Change, Co, D/C, H, New, T), discontinue_of_poe_id, discontinued_by_poe_id, order_provider_id, order_status (Active, Inactive). [MIMIC:modules/hosp/poe.md]
- poe_detail (EAV): poe_id, poe_seq, subject_id, field_name (documented names: Admit to, Indication, Code status, Transfer to, Admit category, Consult Status, Discharge When, Level of Urgency, Discharge Planning, Consult Status Time, Tubes & Drains type), field_value (TEXT, nullable). Note a "Consult Status Time" field holds timestamp-like text values that the TinyEHR date shift may or may not cover (see §8). [MIMIC:modules/hosp/poe_detail.md; ABOUT §1 lists poe but not poe_detail]

#### omr
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id | INTEGER | | | No | | MIMIC:modules/hosp/omr.md |
| chartdate | DATE | | | No | Not in ABOUT's list of shifted tables (see §8) | same; ABOUT |
| seq_num | INTEGER | | | No | Orders same-type results on the same day | same |
| result_name | VARCHAR(100) | | eGFR, Blood Pressure (Lying/Sitting/Standing variants), BMI (kg/m2), BMI, Weight (Lbs), Weight, Height (Inches), Height | No | Duplicate naming variants (BMI vs BMI (kg/m2), etc.) | same |
| result_value | TEXT | text | BP as "sys/dia"; eGFR may be ">60" | No | Mixed numeric/text | same |

#### provider, caregiver
provider.provider_id VARCHAR(10) NOT NULL and caregiver.caregiver_id (documented VARCHAR(10) in caregiver.md but INTEGER in event tables, a type inconsistency) list all ids; no other attributes. [MIMIC:modules/hosp/provider.md; modules/icu/caregiver.md] Row counts in TinyEHR (40,508 and 15,468) are far larger than 100 patients would need, `inferred` that the lists are the full MIMIC-IV id lists, not filtered (§8).

#### d_labitems / d_icd_diagnoses / d_icd_procedures / d_hcpcs / d_items
- d_labitems: itemid, label (VARCHAR 50), fluid, category. `loinc_code` removed in v2.0 (errors found). [MIMIC:modules/hosp/d_labitems.md]
- d_icd_diagnoses, d_icd_procedures: icd_code (CHAR 7), icd_version, long_title. Contain all codes valid at any point 2008-2019, built from the 2020 version plus retired codes. ICD-9 codes 5 chars numeric or E/V-prefixed; ICD-10 3-7 chars starting with a letter. TinyEHR adds decimals to these too. [MIMIC:.../d_icd_*.md; PAPER; ABOUT §2]
- d_hcpcs: code (CHAR 5), category (SMALLINT), long_description, short_description; some definitions unavailable (licensing). [MIMIC:modules/hosp/d_hcpcs.md]
- d_items: itemid (>220000 only), label, abbreviation, linksto (event table; NULL = not yet released), category, unitname, param_type, lownormalvalue, highnormalvalue. [MIMIC:modules/icu/d_items.md]

#### icustays
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| subject_id, hadm_id | INT | | FK | not stated | | MIMIC:modules/icu/icustays.md |
| stay_id | INT | | unique | not stated | Generated; groups ICU transfers within 24h; ICU stays without a heart-rate measurement are excluded (~5% of ICU transfers) | same |
| first_careunit, last_careunit | VARCHAR(20) | | | not stated | Different when moved between ICU types within one stay_id | same |
| intime, outtime | TIMESTAMP(0) | | | not stated | | same |
| los | DOUBLE | fractional days | | not stated | May span several ICU units | same |

#### ICU event tables (chartevents, datetimeevents, inputevents, ingredientevents, outputevents, procedureevents)
All: subject_id, hadm_id, stay_id, caregiver_id (documenter, not the performing provider), itemid → d_items. Source MetaVision only (ICU time).
- chartevents: charttime, storetime, value (VARCHAR 200), valuenum, valueuom, warning (SMALLINT, manually documented warning). Items duplicated from labevents; labevents is ground truth on disagreement. Values like GCS have score in valuenum, text in value.
- datetimeevents: charttime, storetime, value (TIMESTAMP, shifted date), valueuom (almost always "Date"), warning.
- inputevents: starttime, endtime, storetime, amount/amountuom, rate/rateuom, orderid, linkorderid, ordercategoryname, secondaryordercategoryname, ordercomponenttypedescription, ordercategorydescription, patientweight (kg), totalamount/totalamountuom, isopenbag, continueinnextdept (documented in text but absent from column list), statusdescription (Changed, Paused, FinishedRunning, Stopped, Flushed), originalamount, originalrate. Amounts are derived from rates; boluses end 1 minute after start. v2.0 removed all-null columns `cancelreason`.
- ingredientevents: starttime, endtime, storetime, amount/amountuom, rate/rateuom, orderid, linkorderid, statusdescription (adds Rewritten, rows not delivered), originalamount, originalrate; used to total water intake.
- outputevents: charttime, storetime, value (DOUBLE), valueuom; time may be up to an hour after the true event.
- procedureevents: starttime, endtime, storetime, value (duration), valueuom (None, day, hour, min), location, locationcategory, orderid, linkorderid, ordercategoryname/description, patientweight, isopenbag, continueinnextdept, statusdescription (Paused, FinishedRunning, Stopped), originalamount, originalrate (no clear meaning; originalrate only 0 or 1). Existence implies the procedure happened, absence does not imply it did not (optional documentation). `value` should equal endtime−starttime in `valueuom`; instantaneous procedures have a 1-second difference.
Sources: MIMIC:modules/icu/*.md; PAPER (ICU module).

#### noteevents (TinyEHR addition)
| Variable | Type | Unit / code | Allowed values or range | Nullable | Definition and caveats | Source |
|---|---|---|---|---|---|---|
| note_id | string | "{subject_id}-{type_code}-{sequence}" | unique | not stated | Follows MIMIC-IV-Note convention | ABOUT §3 |
| subject_id, hadm_id | integer | | FK | not stated | | ABOUT §3 |
| note_type | string | 14 types: Discharge summary 275, Physician 1,249, Nursing 1,249, Radiology 332, Nursing/other 314, ECG 246, Rehab Services 203, Respiratory 193, Echo 128, General 128, Case Management 109, Nutrition 68, Social Work 51, Consult 35 | | not stated | Sum of listed counts: 4,580 | ABOUT §3 |
| chartdate, charttime | date, datetime | | | not stated | Generated from admission dates | ABOUT §3; README What's New |
| text | text | free text | | not stated | LLM-generated, not clinically validated, may contain wrong ages, fabricated findings, timeline inconsistencies | ABOUT §3; README |
The upstream MIMIC-IV-Note tables (discharge, discharge_detail, radiology, radiology_detail; `___` placeholders for scrubbed PHI) are documented in /data but are not part of TinyEHR; do not apply their definitions to noteevents.

Not documented: column-level definitions for `raw/metadata/date_offsets.csv` beyond "individual patient offsets saved for reproducibility" [ABOUT §1]; MIMIC-IV modules ed, cxr, ecg (described in schema-overview but absent from TinyEHR).

## 3. Cohort rules
- Source cohort: all patients admitted to ED or ICU at BIDMC 2008-2019; adults only (≥18 at first visit); enhanced-protection individuals excluded; multiple MRNs for the same individual merged; neonates removed (v2.0); test-set subjects held out (v2.1) [PAPER; changelog].
- Demo: 100 subject_ids ("only these subject_id are available"); selection rule Not documented [DEMO].
- Identifiers: subject_id (patient; anonymised MRN), hadm_id (hospitalization; anonymised), transfer_id (generated per physical stay), stay_id (generated, groups same-type stays within 24 hours; equals first transfer_id of the stay). hadm_id NULL = data outside an inpatient encounter (outpatient labs, ED-only) [MIMIC:about/concepts.md; PAPER].
- A "patient" = subject_id; "admission" = hadm_id row; "ICU stay" = icustays row, derived from transfers by ICU cost-centre lookup, consecutive ICU transfers merged, requires heart-rate data [PAPER; MIMIC:modules/icu/icustays.md].
- Linkage: death dates linked to Massachusetts vital records by custom fuzzy matching (name, SSN, DOB); 43.6% of candidate individuals linked in full MIMIC-IV, sensitivity-maximising [PAPER].
- TinyEHR preserves referential integrity of subject_id, hadm_id and stay_id; row counts for original tables equal the Demo v2.2 [ABOUT, What Is Not Changed].

## 4. Code lists and terminologies
| Domain | Code system and version | Lookup table or file | Notes on version changes |
|---|---|---|---|
| Diagnoses | ICD-9-CM and ICD-10-CM (`icd_version` 9/10) | d_icd_diagnoses | Dictionary from 2020 release plus retired codes; TinyEHR adds decimal after 3rd character; OMOP format keeps no-decimal form |
| Procedures (billing) | ICD-9 procedure (decimal after 2nd digit) and ICD-10-PCS (7 chars, no decimal) | d_icd_procedures | ICD-9 procedure placement fixed in TinyEHR v0.2.0 |
| DRG | AP-DRG and MS-DRG (`drg_type`) | none; descriptions in table | Descriptions from MassHealth (AP) and HCUP (MS) |
| HCPCS/CPT | HCPCS (mostly CPT) | d_hcpcs | Not all definitions available (licensing) |
| Lab items | Local `itemid` (hospital lab concepts) | d_labitems | 43 itemids changed in v2.0; LOINC removed from d_labitems (v2.0) |
| ICU items | Local MetaVision `itemid` >220000 | d_items | CareVue itemids (<220000) not used |
| Microbiology | Local itemids for specimen, test, organism, antibiotic | none provided (d_micro removed v0.4) | Names carried in `*_name` columns |
| Drugs | NDC (11-digit string), GSN, hospital formulary code | none | Keep as strings |
| Services, admission types, care units | Local text codes | Services listed in MIMIC:modules/hosp/services.md | Admission/discharge locations map loosely to UB-04 |
| Notes | Type codes in note_id (e.g. DS) | ABOUT §3 | |

## 5. Known limitations
| # | Limitation | Affects | Evidence | Source |
|---|---|---|---|---|
| **Population gaps** | | | | |
| L1 | 100 patients, one centre; not representative; no statistical inference about any population | all | Stated | README; DEMO |
| L2 | Out-of-hospital death captured only to 1 year post-discharge; NULL `dod` does not mean alive beyond 1 year; death linkage is fuzzy and sensitivity-maximising | patients.dod; survival analyses | Stated | MIMIC:modules/hosp/patients.md; PAPER |
| L3 | ICU stays lacking heart rate excluded (~5% of ICU transfers); ICU data exist only while in ICU | icustays, icu events | Stated | MIMIC:modules/icu/icustays.md |
| **Definition changes** | | | | |
| L4 | IDs regenerated across versions (transfer_id, stay_id in v1.0; micro_specimen_id v0.4; subject_id/hadm_id vs MIMIC-III), so not comparable across releases | IDs | Stated | changelog; PAPER |
| L5 | Upstream `dod` rule changed v1.0→v2.0 (in-hospital only → state records); lab values moved from comments to value in v2.0; inputevents amount bug fixed v0.2 | dod, labevents | Stated | changelog |
| L6 | Documents disagree on age cap: patients.md says anchor_age is 91 when >89; concepts.md says age fixed at 300 and DOB before 1900 | anchor_age | Conflict, both reported | MIMIC:modules/hosp/patients.md; about/concepts.md |
| L7 | TinyEHR ICD format (decimal) differs from MIMIC-IV (no decimal) and its own OMOP format; joins to external MIMIC code lists need normalisation | diagnoses_icd, procedures_icd, d_icd_* | Stated | ABOUT §2 |
| **De-identification effects** | | | | |
| L8 | Dates shifted per patient (TinyEHR second shift on top of MIMIC's); calendar year/season/weekday are not real; intervals within a patient preserved; true year known only to a 3-year band; ages >89 capped; race aggregated; free text PHI replaced with `___` | all dates, anchor_*, comments, text | Stated | ABOUT §1; PAPER; MIMIC:about/concepts.md |
| L9 | Leap-day edge case: Feb 29 becomes Feb 28 when the target year is not a leap year, which can alter exact day intervals by one day (`inferred` from ABOUT) | all shifted dates | Stated mechanism, effect inferred | ABOUT §1 |
| **Missingness** | | | | |
| L10 | eMAR not available for all patients: docs say implemented 2011-2013 (emar page) vs deployed 2014-2016, all units by 2016 (paper); both reported | emar, emar_detail | Conflict | MIMIC:modules/hosp/emar.md; PAPER |
| L11 | `hadm_id` missing for some labs/micro that fall inside an admission window (~2% labs, ~4% micro in full MIMIC v2.1); emar rows outside admin times formerly lacked hadm_id | labevents, microbiologyevents, emar | Stated | labevents.md; microbiologyevents.md; changelog v2.2 |
| L12 | Negative microbiology results usually NULL (except itemid 90856); procedureevents absence is not evidence of absence; micro keeps only final result, interim results lost | microbiologyevents, procedureevents | Stated | microbiologyevents.md; procedureevents.md; PAPER |
| L13 | `d_items.linksto` NULL = data planned for future release | d_items | Stated | d_items.md |
| **Measurement and coding quality** | | | | |
| L14 | LLM-generated notes: unvalidated, may hallucinate ages, findings, timelines; not equivalent to real notes | noteevents | Stated | README; ABOUT §3 |
| L15 | Diagnosis `seq_num` is billing priority, not clinical importance; max 39 diagnoses | diagnoses_icd | Stated | diagnoses_icd.md; PAPER |
| L16 | Charttime is hour-block charting and may differ from true measurement time; storetime can precede charttime; lab charttime is collection time | *_events | Stated | concepts.md; labevents.md |
| L17 | Duplicated items between labevents and chartevents may disagree; labevents wins | labs | Stated | chartevents.md |
| L18 | Organ-donor accounts: separate short/negative-LOS admissions, duplicated deathtime; deathtime vs dischtime discrepancies from typos | admissions | Stated | admissions.md |
| L19 | Inputs: volumes derived from rates; Rewritten rows not delivered; originalrate/originalamount in procedureevents meaningless | ICU inputs | Stated | inputevents.md; ingredientevents.md; procedureevents.md |
| L20 | OMR has overlapping result_name variants and mixed text/numeric values | omr | Stated | omr.md |
| L21 | `doses_per_24_hrs` misleading for continuous infusions | pharmacy | Stated | pharmacy.md |
| L22 | Documented-but-unverified: OMOP-only effects (852 vs 275 visits, mixed condition_source_value) do not affect the MIMIC-format files | OMOP only | Stated | ABOUT Design Decisions |

## 6. DQ rules seed
Hypotheses derived from documentation, not measured quality. Machine-readable version: `rules-seed.json` (one `rules.json` per table, format of `data-quality-evaluation/references/rules-format.md`; `source` keys are ignored by the profiler). Rules marked * conflict-prone or inferred; expect documented exceptions.

| Table | Rule | Source |
|---|---|---|
| patients | subject_id not null and unique | patients.md |
| patients | anchor_age 18-91, integer (*conflict with 300 cap; adults only per PAPER) | patients.md; concepts.md; PAPER |
| patients | anchor_year_group matches "YYYY - YYYY" | patients.md |
| patients | dod null or ≥ some admission (cross-table, not seeded) | inferred |
| admissions | hadm_id unique, not null, 2000000-2999999 (*TinyEHR may differ) | admissions.md |
| admissions | admission_type in the 9 listed values | admissions.md |
| admissions | hospital_expire_flag in 0/1 | admissions.md |
| admissions | dischtime ≥ admittime (* organ-donor exceptions documented) | admissions.md |
| admissions | deathtime null or hospital_expire_flag = 1 (*inferred) | admissions.md |
| admissions | edouttime ≥ edregtime (*inferred) | admissions.md |
| transfers | transfer_id not null unique; eventtype in ed/admit/transfer/discharge; outtime ≥ intime | transfers.md; changelog v2.0 |
| services | curr_service in 21 listed codes | services.md |
| diagnoses_icd / procedures_icd | icd_version in 9/10; seq_num ≥ 1; diagnoses seq_num ≤ 39; TinyEHR decimal format regex | PAPER; ABOUT §2 |
| labevents | labevent_id unique not null; storetime ≥ charttime; ref_range_lower ≤ ref_range_upper; priority in ROUTINE/STAT | labevents.md |
| microbiologyevents | interpretation in S/R/I/P; chartdate not null | microbiologyevents.md |
| emar | emar_id unique; storetime ≥ charttime | emar.md |
| poe | poe_id unique; order_status in Active/Inactive | poe.md |
| icustays | stay_id unique; outtime ≥ intime; los > 0 | icustays.md |
| chartevents/ICU | valuenum numeric when value numeric (not seeded) | chartevents.md |
| procedureevents | valueuom in None/day/hour/min | procedureevents.md |
| inputevents | statusdescription in 5 documented values | inputevents.md |
| d_items | itemid > 220000 | d_items.md |

## 7. Literature findings
Queries run on PubMed (2026-10-09): `MIMIC-IV data quality OR limitations OR bias`; `MIMIC-IV validation`; `MIMIC-IV race ethnicity documentation OR missingness OR ICD coding`; `TinyEHR OR "MIMIC-IV demo"`; title-restricted `"MIMIC-IV"[Title] AND (quality OR bias OR limitations OR validation OR accuracy)`; `MIMIC electronic health record database data quality assessment pitfalls`; `MIMIC-IV mortality date of death linkage state death records out-of-hospital`.
| Fact | Reference | Pedigree question it answers |
|---|---|---|
| The MIMIC-IV Demo is used as a teaching dataset for ETL pipelines in a medical data science course. | Meyer-Eschenbach F et al., 2026, PMID 42175325, doi:10.3233/SHTI260657 (Stud Health Technol Inform) | Intended use |
| No peer-reviewed validation of TinyEHR or of the generated notes was found. | search above | How measured/validated |
| Searches on data quality, bias and death-linkage returned either no results or mostly ML prediction studies built on MIMIC-IV (not about its quality); none were adopted. | search above | Population, coding quality |

## 8. Open questions
| # | Unanswered question | What would answer it |
|---|---|---|
| Q1 | How were the 100 demo patients selected from MIMIC-IV, and are they representative of the ICU/ED cohort? | PhysioNet demo project page or authors |
| Q2 | Was `patients.anchor_year` also shifted by TinyEHR? ABOUT lists only `dod` as modified for patients and says anchor_year_group is unchanged, but README illustrations show realistic anchor years. | TinyEHR author / build scripts |
| Q3 | Were `omr.chartdate`, `poe_detail` timestamp-like `field_value` text, `emar_detail`/`pharmacy` datetimes, `microbiologyevents.chartdate/storedate` and `noteevents` dates shifted? ABOUT's modified-table list omits omr, poe_detail and mentions others inconsistently. | TinyEHR build scripts |
| Q4 | Which `date_offsets.csv` columns exist, and does it allow reversing the shift (privacy and licensing consequence)? | Inspect header only, or ask authors |
| Q5 | Do `provider` (40,508) and `caregiver` (15,468) lists include ids not referenced by the 100 patients? Does `services` contain newborn codes? | Profile referential integrity |
| Q6 | eMAR rollout: 2011-2013 (emar page) vs 2014-2016 (PAPER). | MIMIC authors; check data by period |
| Q7 | Age cap: 91 vs 300 for >89 (L6). | Profile `anchor_age` |
| Q8 | Documented value lists for gender, race, insurance, language, marital_status, admission_location, careunit, flag. | Profile (distinct counts only) |
| Q9 | Primary/unique keys for services, drgcodes, prescriptions, chartevents and other event tables are not documented. | Profile; MIMIC build scripts |
| Q10 | Whether the generated notes' content is consistent with structured data (ages, diagnoses, dates). | Targeted audit; unmeasured |
| Q11 | Does TinyEHR's version history (v0.1 vs v0.2.0) affect the files fetched on 2026-10-08? README says v0.2.0 corrected ICD procedure decimals, types, notes. | Manifest commit check |
| Q12 | Documentation counts the "33 tables" including date-shift metadata; ABOUT lists 32 table rows (22 hosp + 9 icu + noteevents) | ABOUT; file listing |
| Q13 | Published literature on data-quality/bias of MIMIC-IV not found in PubMed with the queries tried. | Broader search (Embase, Google Scholar) |

## Sources
Converted (58, under /data/_converted; originals under /data): tinyehr/README.md, tinyehr/ABOUT_THE_DATA.md; physionet_mimic_iv_demo_v2.2/{README.txt, LICENSE.txt, SHA256SUMS.txt}; mimic_iv_paper/Johnson_2023_MIMIC-IV_Scientific_Data.pdf (text extraction; tables not verified against the PDF layout); manifest_00_get_the_data.csv (file metadata only); mimic_iv_official_docs: glossary, iv/index, about/{index, concepts, schema-overview, whatsnew, changelog}, modules/index, hosp/ (index + 22 table pages), icu/ (index + 9 table pages), note/ (index + 4 table pages), _includes/ (5).
Not converted: none. Not used: SHA256SUMS.txt (checksums only); LICENSE.txt beyond the licence name.
Data files listed but never opened (34): raw/metadata/date_offsets.csv; raw/tinyehr_mimic_format/hosp (22 CSVs), icu (9 CSVs), notes/noteevents.csv; documentation/physionet_mimic_iv_demo_v2.2/demo_subject_id.csv. Sizes are in /data/_converted/_inventory.md.
