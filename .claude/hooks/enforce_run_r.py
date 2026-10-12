#!/usr/bin/env python3
"""PreToolUse hook (Bash): enforce run_r.sh for all R script execution.

Blocks direct `Rscript`/`R CMD BATCH` invocations so every R run goes through
.claude/scripts/run_r.sh (consistent logging, archival, error surfacing).
Exit 2 = block, stderr is fed back to Claude.
"""
import json
import re
import sys


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # never break the session on malformed input

    if payload.get("tool_name") != "Bash":
        return 0

    command = payload.get("tool_input", {}).get("command", "") or ""

    # Allow the sanctioned wrapper itself
    if ".claude/scripts/run_r.sh" in command:
        return 0

    # Block direct Rscript / R CMD BATCH execution of .R files
    direct_r = re.search(r"(^|[;&|]\s*)(Rscript|R\s+CMD\s+BATCH)\b", command)
    if direct_r:
        sys.stderr.write(
            "BLOCKED by enforce_run_r hook: direct R execution is not allowed.\n"
            "Use the standard wrapper instead:\n"
            "  bash .claude/scripts/run_r.sh <path_to_script.R>\n"
            "It handles log creation, archival, timing, and error display in 6_Logs/.\n"
        )
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
