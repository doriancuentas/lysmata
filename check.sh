#!/usr/bin/env bash
# Lint, format, and security scan. Run with --help for usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAF_DIR="$SCRIPT_DIR/.laf"
LOG_DIR="$LAF_DIR/logs"
VERBOSE=false
EXIT_CODE=0
RUN_ID=$(date +%Y%m%d_%H%M%S)_$$
START_TIME=$(date +%s)

# Temp directory with cleanup trap (security fix: ensures cleanup on exit)
TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Common exclusion directories (DRY: used in find commands)
EXCLUDE_DIRS=(".venv" "venv" ".git" "node_modules" "__pycache__")

show_usage() {
    cat << 'EOF'
Lysmata - Code Quality Check

Usage: ./check.sh [--verbose] [--logs] [--logs-clear] [--help]

Runs all checks (offline, no internet required):
  *.ts/*.tsx/*.js   -> eslint + prettier (lint + format + security)
  *.py              -> ruff (lint + format + security)
  *.yaml/*.yml      -> yamllint
  *.html            -> curlylint
  requirements.txt  -> pip-audit (dependency vulnerabilities)

Note: TS/JS security requires eslint-plugin-security in your project.

Options:
  --verbose      Show detailed errors (default: summary only)
  --logs         Show usage insights from recent runs
  --logs-clear   Clear all logs
  --help         Show this message

Requirements: pip install -r .laf/requirements.txt
EOF
}

# Initialize logging
init_logs() {
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/$RUN_ID.json"
    echo '{"run_id":"'"$RUN_ID"'","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","project":"'"$(basename "$(pwd)")"'","cwd":"'"$(pwd)"'","detection":{},"tools":[],"exclusions":{}}' > "$LOG_FILE"
}

# Log detection results
log_detection() {
    local lang="$1" count="$2" patterns="$3"
    local tmp="$TMP_DIR/jq_out"
    jq --arg l "$lang" --arg c "$count" --arg p "$patterns" \
        '.detection[$l] = {"count": ($c|tonumber), "patterns": $p}' "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
}

# Log tool execution
log_tool() {
    local tool="$1" status="$2" files="$3" duration="${4:-0}"
    local tmp="$TMP_DIR/jq_out"
    jq --arg t "$tool" --arg s "$status" --arg f "$files" --arg d "$duration" \
        '.tools += [{"tool": $t, "status": $s, "files": ($f|tonumber), "duration_sec": ($d|tonumber)}]' "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
}

# Log exclusion patterns hit
log_exclusion() {
    local pattern="$1" count="$2"
    local tmp="$TMP_DIR/jq_out"
    jq --arg p "$pattern" --arg c "$count" \
        '.exclusions[$p] = ($c|tonumber)' "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
}

# Finalize log with summary
finalize_log() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local tmp="$TMP_DIR/jq_out"
    jq --arg d "$duration" --arg e "$EXIT_CODE" \
        '.duration_sec = ($d|tonumber) | .exit_code = ($e|tonumber)' "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
}

# Show logs insights
show_logs() {
    if [[ ! -d "$LOG_DIR" ]] || [[ -z "$(ls -A "$LOG_DIR" 2>/dev/null)" ]]; then
        echo "No logs found. Run ./check.sh first."
        exit 0
    fi

    echo "Lysmata Usage Insights"
    echo "======================"
    echo ""

    # Aggregate stats from recent logs
    local total_runs=$(ls -1 "$LOG_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
    echo "Total runs logged: $total_runs"
    echo ""

    # Language detection frequency
    echo "Language Detection (across all runs):"
    jq -s '[.[].detection | to_entries[]] | group_by(.key) | map({lang: .[0].key, runs: length, avg_files: ([.[].value.count] | add / length | floor)}) | sort_by(-.runs)[] | "  \(.lang): \(.runs) runs, avg \(.avg_files) files"' "$LOG_DIR"/*.json 2>/dev/null | tr -d '"' || echo "  (no data)"
    echo ""

    # Tool success/failure rates
    echo "Tool Results:"
    jq -s '[.[].tools[]] | group_by(.tool) | map({tool: .[0].tool, total: length, ok: [.[] | select(.status == "ok" or .status == "done")] | length}) | sort_by(-.total)[] | "  \(.tool): \(.ok)/\(.total) success"' "$LOG_DIR"/*.json 2>/dev/null | tr -d '"' || echo "  (no data)"
    echo ""

    # Exclusion patterns
    echo "Files Excluded (total across runs):"
    jq -s '[.[].exclusions | to_entries[]] | group_by(.key) | map({pattern: .[0].key, total: [.[].value] | add}) | sort_by(-.total)[] | "  \(.pattern): \(.total) files"' "$LOG_DIR"/*.json 2>/dev/null | tr -d '"' || echo "  (no data)"
    echo ""

    # Recent runs
    echo "Recent Runs:"
    ls -1t "$LOG_DIR"/*.json 2>/dev/null | head -5 | while read -r f; do
        jq -r '"  \(.timestamp | split("T")[0]) \(.project): \(.duration_sec)s, exit \(.exit_code)"' "$f" 2>/dev/null || true
    done
    echo ""

    # Improvement suggestions
    echo "Insights for Improvement:"
    # Check for consistently failing tools
    local failing=$(jq -s '[.[].tools[] | select(.status == "issues" or .status == "vulnerabilities")] | group_by(.tool) | map(select(length > 2)) | .[0].tool // empty' "$LOG_DIR"/*.json 2>/dev/null | tr -d '"')
    [[ -n "$failing" ]] && echo "  - Tool '$failing' frequently has issues - consider reviewing config"

    # Check for large exclusion counts
    local big_exclude=$(jq -s '[.[].exclusions | to_entries[] | select(.value > 100)] | .[0].key // empty' "$LOG_DIR"/*.json 2>/dev/null | tr -d '"')
    [[ -n "$big_exclude" ]] && echo "  - Pattern '$big_exclude' excludes many files - verify this is intended"

    # Check for missing language support
    local no_ts=$(jq -s '[.[].detection.typescript // .[].detection.javascript] | map(select(. != null)) | length' "$LOG_DIR"/*.json 2>/dev/null)
    local no_py=$(jq -s '[.[].detection.python] | map(select(. != null)) | length' "$LOG_DIR"/*.json 2>/dev/null)
    [[ "$no_ts" == "0" ]] && [[ "$no_py" == "0" ]] && echo "  - No TS/JS or Python detected - lysmata works best with these"

    echo ""
}

# Clear logs
clear_logs() {
    if [[ -d "$LOG_DIR" ]]; then
        rm -rf "$LOG_DIR"
        echo "Logs cleared."
    else
        echo "No logs to clear."
    fi
    exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)   VERBOSE=true; shift ;;
        --logs)         show_logs; exit 0 ;;
        --logs-clear)   clear_logs ;;
        --help|-h)      show_usage; exit 0 ;;
        *)              echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Check .laf directory exists
if [[ ! -d "$LAF_DIR" ]]; then
    echo "Error: .laf/ directory not found"
    exit 1
fi

# Initialize logging (requires jq)
if command -v jq &>/dev/null; then
    init_logs
    LOGGING_ENABLED=true
else
    LOGGING_ENABLED=false
fi

# Check required tools
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "Error: $1 not found"
        echo "Fix: pip install -r $LAF_DIR/requirements.txt"
        exit 1
    fi
}

# Build find exclusion arguments from EXCLUDE_DIRS
build_find_excludes() {
    local excludes=""
    for dir in "${EXCLUDE_DIRS[@]}"; do
        excludes="$excludes -not -path \"./$dir/*\""
    done
    echo "$excludes"
}

# Count excluded files for logging
count_excluded() {
    local pattern="$1" dir="$2"
    find . -type f -name "$pattern" -path "./$dir/*" 2>/dev/null | wc -l | tr -d ' '
}

# Log all exclusions for a file pattern
log_exclusions_for() {
    [[ "$LOGGING_ENABLED" != true ]] && return 0
    local pattern="$1"
    for dir in "${EXCLUDE_DIRS[@]}"; do
        local cnt=$(count_excluded "$pattern" "$dir")
        [[ "$cnt" -gt 0 ]] && log_exclusion "$dir" "$cnt"
    done
    return 0
}

# Detect files (using EXCLUDE_DIRS)
has_files() {
    local cmd="find . -type f -name \"$1\""
    for dir in "${EXCLUDE_DIRS[@]}"; do
        cmd="$cmd -not -path \"./$dir/*\""
    done
    eval "$cmd" 2>/dev/null | head -1 | grep -q .
}

count_files() {
    local cmd="find . -type f -name \"$1\""
    for dir in "${EXCLUDE_DIRS[@]}"; do
        cmd="$cmd -not -path \"./$dir/*\""
    done
    eval "$cmd" 2>/dev/null | wc -l | tr -d ' '
}

echo "Lysmata - Code Quality Check"
echo "============================"
echo ""

# TypeScript/JavaScript: ESLint + Prettier (with security)
if has_files "*.ts" || has_files "*.tsx" || has_files "*.js"; then
    ts_count=$(($(count_files "*.ts") + $(count_files "*.tsx") + $(count_files "*.js")))

    # Log detection
    [[ "$LOGGING_ENABLED" == true ]] && {
        log_detection "typescript" "$(count_files "*.ts")" "*.ts"
        log_detection "tsx" "$(count_files "*.tsx")" "*.tsx"
        log_detection "javascript" "$(count_files "*.js")" "*.js"
        log_exclusions_for "*.ts"
        log_exclusions_for "*.tsx"
        log_exclusions_for "*.js"
    }

    # Check for package manager (pnpm preferred, fallback to npm)
    if command -v pnpm &>/dev/null && [[ -f "pnpm-lock.yaml" ]]; then
        PM="pnpm"
    elif command -v npm &>/dev/null; then
        PM="npm"
    else
        echo "[ts/js] WARNING: $ts_count TS/JS files found but no package manager (npm/pnpm) available"
        echo "        Install npm or pnpm to enable linting and formatting"
        PM=""
    fi

    if [[ -n "$PM" ]]; then
        # Format with prettier (if available)
        if $PM exec prettier --version &>/dev/null 2>&1; then
            echo -n "[prettier] $ts_count files... "
            tool_start=$(date +%s)
            # || true: prettier returns non-zero when files change, which is expected
            $PM exec prettier --write "**/*.{ts,tsx,js,json}" --log-level=error 2>/dev/null || true
            tool_end=$(date +%s)
            echo "DONE"
            [[ "$LOGGING_ENABLED" == true ]] && log_tool "prettier" "done" "$ts_count" "$((tool_end - tool_start))"
        fi

        # Lint + Fix with eslint (if available)
        if $PM exec eslint --version &>/dev/null 2>&1; then
            echo -n "[eslint:fix] $ts_count files... "
            tool_start=$(date +%s)
            # || true: eslint --fix returns non-zero when it fixes issues, which is expected
            $PM exec eslint --fix . --quiet 2>/dev/null || true
            tool_end=$(date +%s)
            echo "DONE"
            [[ "$LOGGING_ENABLED" == true ]] && log_tool "eslint:fix" "done" "$ts_count" "$((tool_end - tool_start))"

            # Check (includes security rules if eslint-plugin-security installed)
            echo -n "[eslint:check] $ts_count files... "
            tool_start=$(date +%s)
            eslint_status="ok"
            if [[ "$VERBOSE" == true ]]; then
                output=$($PM exec eslint . 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                    eslint_status="issues"
                    echo "$output"
                    echo ""
                }
            else
                output=$($PM exec eslint . --quiet 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                    eslint_status="issues"
                }
            fi
            tool_end=$(date +%s)
            [[ "$eslint_status" == "ok" ]] && echo "OK"
            [[ "$LOGGING_ENABLED" == true ]] && log_tool "eslint:check" "$eslint_status" "$ts_count" "$((tool_end - tool_start))"
        fi

        # Type check (if tsc available)
        if $PM exec tsc --version &>/dev/null 2>&1; then
            echo -n "[tsc] type checking... "
            tool_start=$(date +%s)
            tsc_status="ok"
            if [[ "$VERBOSE" == true ]]; then
                output=$($PM exec tsc --noEmit 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                    tsc_status="issues"
                    echo "$output"
                    echo ""
                }
            else
                output=$($PM exec tsc --noEmit 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                    tsc_status="issues"
                }
            fi
            tool_end=$(date +%s)
            [[ "$tsc_status" == "ok" ]] && echo "OK"
            [[ "$LOGGING_ENABLED" == true ]] && log_tool "tsc" "$tsc_status" "$ts_count" "$((tool_end - tool_start))"
        fi
    fi
fi

# Python: ruff (lint + format + security)
if has_files "*.py"; then
    check_tool ruff
    py_count=$(count_files "*.py")

    # Log detection
    [[ "$LOGGING_ENABLED" == true ]] && {
        log_detection "python" "$py_count" "*.py"
        log_exclusions_for "*.py"
    }

    # Fix
    echo -n "[ruff:fix] $py_count files... "
    tool_start=$(date +%s)
    # || true: ruff fix returns non-zero when it fixes issues, which is expected
    ruff check --config "$LAF_DIR/ruff.toml" --fix --quiet . 2>/dev/null || true
    tool_end=$(date +%s)
    echo "DONE"
    [[ "$LOGGING_ENABLED" == true ]] && log_tool "ruff:fix" "done" "$py_count" "$((tool_end - tool_start))"

    # Format
    echo -n "[ruff:format] $py_count files... "
    tool_start=$(date +%s)
    # || true: ruff format returns non-zero when it formats files, which is expected
    ruff format --config "$LAF_DIR/ruff.toml" --quiet . 2>/dev/null || true
    tool_end=$(date +%s)
    echo "DONE"
    [[ "$LOGGING_ENABLED" == true ]] && log_tool "ruff:format" "done" "$py_count" "$((tool_end - tool_start))"

    # Check (includes security S rules)
    echo -n "[ruff:check] $py_count files... "
    tool_start=$(date +%s)
    ruff_status="ok"
    if [[ "$VERBOSE" == true ]]; then
        output=$(ruff check --config "$LAF_DIR/ruff.toml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            ruff_status="issues"
            echo "$output"
            echo ""
        }
    else
        output=$(ruff check --config "$LAF_DIR/ruff.toml" --quiet . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            ruff_status="issues"
        }
    fi
    tool_end=$(date +%s)
    [[ "$ruff_status" == "ok" ]] && echo "OK"
    [[ "$LOGGING_ENABLED" == true ]] && log_tool "ruff:check" "$ruff_status" "$py_count" "$((tool_end - tool_start))"
fi

# YAML: yamllint
if has_files "*.yaml" || has_files "*.yml"; then
    check_tool yamllint
    yaml_count=$(($(count_files "*.yaml") + $(count_files "*.yml")))

    # Log detection
    [[ "$LOGGING_ENABLED" == true ]] && {
        log_detection "yaml" "$yaml_count" "*.yaml,*.yml"
        log_exclusions_for "*.yaml"
        log_exclusions_for "*.yml"
    }

    echo -n "[yamllint] $yaml_count files... "
    tool_start=$(date +%s)
    yaml_status="ok"
    if [[ "$VERBOSE" == true ]]; then
        output=$(yamllint -c "$LAF_DIR/yamllint.yaml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            yaml_status="issues"
            echo "$output"
            echo ""
        }
    else
        output=$(yamllint -c "$LAF_DIR/yamllint.yaml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            yaml_status="issues"
        }
    fi
    tool_end=$(date +%s)
    [[ "$yaml_status" == "ok" ]] && echo "OK"
    [[ "$LOGGING_ENABLED" == true ]] && log_tool "yamllint" "$yaml_status" "$yaml_count" "$((tool_end - tool_start))"
fi

# HTML: curlylint
if has_files "*.html"; then
    check_tool curlylint
    html_count=$(count_files "*.html")

    # Log detection
    [[ "$LOGGING_ENABLED" == true ]] && {
        log_detection "html" "$html_count" "*.html"
        log_exclusions_for "*.html"
    }

    echo -n "[curlylint] $html_count files... "
    tool_start=$(date +%s)
    html_status="ok"
    if [[ "$VERBOSE" == true ]]; then
        output=$(curlylint --config "$LAF_DIR/curlylint.toml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            html_status="issues"
            echo "$output"
            echo ""
        }
    else
        output=$(curlylint --config "$LAF_DIR/curlylint.toml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            html_status="issues"
        }
    fi
    tool_end=$(date +%s)
    [[ "$html_status" == "ok" ]] && echo "OK"
    [[ "$LOGGING_ENABLED" == true ]] && log_tool "curlylint" "$html_status" "$html_count" "$((tool_end - tool_start))"
fi

# Dependencies: pip-audit
REQ_FILES=()
while IFS= read -r -d '' file; do
    REQ_FILES+=("$file")
done < <(find . -maxdepth 2 -name "requirements*.txt" \
    -not -path "./.venv/*" \
    -not -path "./venv/*" \
    -not -path "./.laf/*" \
    -print0 2>/dev/null)

if [[ ${#REQ_FILES[@]} -gt 0 ]]; then
    REQ_FILES=($(printf "%s\n" "${REQ_FILES[@]}" | sort -u))
    check_tool pip-audit

    # Log detection
    [[ "$LOGGING_ENABLED" == true ]] && log_detection "requirements" "${#REQ_FILES[@]}" "requirements*.txt"

    for req_file in "${REQ_FILES[@]}"; do
        echo -n "[pip-audit] $req_file... "
        tool_start=$(date +%s)
        audit_status="ok"
        if [[ "$VERBOSE" == true ]]; then
            output=$(pip-audit -r "$req_file" 2>&1) || {
                echo "VULNERABILITIES"
                EXIT_CODE=1
                audit_status="vulnerabilities"
                echo "$output"
                echo ""
            }
        else
            output=$(pip-audit -r "$req_file" --progress-spinner=off 2>&1) || {
                echo "VULNERABILITIES"
                EXIT_CODE=1
                audit_status="vulnerabilities"
            }
        fi
        tool_end=$(date +%s)
        [[ "$audit_status" == "ok" ]] && echo "OK"
        [[ "$LOGGING_ENABLED" == true ]] && log_tool "pip-audit" "$audit_status" "1" "$((tool_end - tool_start))"
    done
elif [[ -f "pyproject.toml" ]]; then
    check_tool pip-audit

    # Log detection
    [[ "$LOGGING_ENABLED" == true ]] && log_detection "pyproject" "1" "pyproject.toml"

    echo -n "[pip-audit] pyproject.toml... "
    tool_start=$(date +%s)
    audit_status="ok"
    if [[ "$VERBOSE" == true ]]; then
        output=$(pip-audit 2>&1) || {
            echo "VULNERABILITIES"
            EXIT_CODE=1
            audit_status="vulnerabilities"
            echo "$output"
            echo ""
        }
    else
        output=$(pip-audit --progress-spinner=off 2>&1) || {
            echo "VULNERABILITIES"
            EXIT_CODE=1
            audit_status="vulnerabilities"
        }
    fi
    tool_end=$(date +%s)
    [[ "$audit_status" == "ok" ]] && echo "OK"
    [[ "$LOGGING_ENABLED" == true ]] && log_tool "pip-audit" "$audit_status" "1" "$((tool_end - tool_start))"
fi

# Finalize logging
[[ "$LOGGING_ENABLED" == true ]] && finalize_log

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "All checks passed"
else
    echo "Issues found (run with --verbose for details)"
fi

exit $EXIT_CODE
