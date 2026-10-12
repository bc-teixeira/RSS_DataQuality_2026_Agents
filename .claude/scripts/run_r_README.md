# .claude/scripts/run_r.sh - R Script Execution with Log Management

## Purpose
Execute R scripts with automatic log management, archival, and real-time output display.

## Usage
```bash
bash .claude/scripts/run_r.sh <path_to_r_script>
```

## Examples
```bash
# Run a cohort script
bash .claude/scripts/run_r.sh 2_Code/01_Cohort.R

# Run a test script
bash .claude/scripts/run_r.sh 4_Tests/01_Cohort_Tests.R
```

## Features

### ✅ Automatic Log Management
- **Log Location**: `logs/<scriptname>_YYYYMMDD_HHMMSS.log`
- **Archive Location**: `logs/archive/`
- **Behavior**: Previous logs for the same script are automatically moved to archive before each run

### ✅ Real-Time Output Display
- Script output displays in terminal as it runs (using `tee`)
- Full output is simultaneously saved to log file
- No need to wait until completion to see progress

### ✅ Status Reporting
- **Success**: Green checkmark with execution time
- **Failure**: Red X with last 30 lines of error log
- Color-coded output for easy visual scanning

### ✅ Error Handling
- Validates script exists before execution
- Exits with appropriate error codes
- Displays helpful error messages

## Log Structure

### Main Log Directory (`logs/`)
Contains only the **latest log** for each R script:
```
logs/
├── 01_Cohort_20251027_143022.log          # Latest run
├── 02_Attrition_20251027_143155.log       # Latest run
└── 03_Analysis_20251027_143340.log        # Latest run
```

### Archive Directory (`logs/archive/`)
Contains **all previous logs**:
```
logs/archive/
├── 01_Cohort_20251027_120000.log          # Previous run
├── 01_Cohort_20251027_130000.log          # Previous run
├── 02_Attrition_20251027_125500.log       # Previous run
└── ...
```

## Mandatory Usage Rule

`CLAUDE.md` requires **all R code execution** to use this script:

```bash
# MANDATORY pattern
bash .claude/scripts/run_r.sh 2_Code/01_Cohort.R
```

This ensures:
- Consistent log management across all analysis steps
- Automatic archival of previous runs
- Easy debugging with timestamped logs
- Audit trail of all script executions

## Exit Codes
- `0` - Success
- `1` - Script execution failed or file not found
- `127` - Script not found or permissions error

## Best Practices

### In R Scripts
Include informative `message()` statements for step-by-step tracking:

```r
message("Step 1: Loading enrollment data...")
# ... code ...
message("  → Loaded ", nrow(data), " patients")

message("Step 2: Applying filters...")
# ... code ...
message("  → Remaining: ", nrow(filtered), " patients")
```

### When Running Code
Always use `.claude/scripts/run_r.sh` instead of direct `Rscript` calls:

```bash
# ❌ DON'T
Rscript 2_Code/01_Cohort.R

# ✅ DO
bash .claude/scripts/run_r.sh 2_Code/01_Cohort.R
```

## Troubleshooting

### "Script not found" Error
- Verify the path to the R script is correct
- Use relative paths from workspace root (e.g., `2_Code/script.R`)

### "Permission denied"
- Ensure `.claude/scripts/run_r.sh` is executable: `chmod +x .claude/scripts/run_r.sh`

### No Output Displayed
- Check that R script uses `message()` or `cat()` for output
- Verify script doesn't redirect output elsewhere

## Technical Details

- **Timestamp Format**: `YYYYMMDD_HHMMSS` (file-safe, sortable)
- **Error Handling**: `set -e`, `set -u`, `set -o pipefail`
- **Output Capture**: `tee` for simultaneous display and logging
- **Archive Strategy**: Move all previous logs with same base name to archive before each run
