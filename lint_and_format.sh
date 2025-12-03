#!/usr/bin/env bash
# Lint and format codebase. Run with --help for usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAF_DIR="$SCRIPT_DIR/.laf"
VERBOSE=false
EXIT_CODE=0

show_usage() {
    cat << 'EOF'
Lysmata - Lint and Format

Usage: ./lint_and_format.sh [--verbose] [--help]

Detects file types and runs appropriate tools:
  *.py        -> ruff (lint + format)
  *.yaml/yml  -> yamllint
  *.html      -> curlylint

Options:
  --verbose   Show detailed errors (default: summary only)
  --help      Show this message

Requirements: pip install -r .laf/requirements.txt
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        --help|-h)    show_usage; exit 0 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Check .laf directory exists
if [[ ! -d "$LAF_DIR" ]]; then
    echo "Error: .laf/ directory not found"
    exit 1
fi

# Check required tools
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "Error: $1 not found"
        echo "Fix: pip install -r $LAF_DIR/requirements.txt"
        exit 1
    fi
}

# Detect files
has_files() {
    find . -type f -name "$1" \
        -not -path "./.venv/*" \
        -not -path "./venv/*" \
        -not -path "./.git/*" \
        -not -path "./node_modules/*" \
        -not -path "./__pycache__/*" \
        2>/dev/null | head -1 | grep -q .
}

count_files() {
    find . -type f -name "$1" \
        -not -path "./.venv/*" \
        -not -path "./venv/*" \
        -not -path "./.git/*" \
        -not -path "./node_modules/*" \
        -not -path "./__pycache__/*" \
        2>/dev/null | wc -l | tr -d ' '
}

# Run tool and capture result
run_tool() {
    local name="$1"
    local count="$2"
    shift 2

    echo -n "[$name] $count files... "

    local output
    local tool_exit=0
    output=$("$@" 2>&1) || tool_exit=$?

    if [[ $tool_exit -eq 0 ]]; then
        echo "OK"
    else
        echo "ISSUES"
        EXIT_CODE=1
        if [[ "$VERBOSE" == true ]]; then
            echo "$output"
            echo ""
        fi
    fi
}

echo "Lysmata - Lint & Format"
echo "======================="
echo ""

# Python: ruff
if has_files "*.py"; then
    check_tool ruff
    py_count=$(count_files "*.py")

    echo -n "[ruff:fix] $py_count files... "
    ruff check --config "$LAF_DIR/ruff.toml" --fix --quiet . 2>/dev/null || true
    echo "DONE"

    echo -n "[ruff:format] $py_count files... "
    ruff format --config "$LAF_DIR/ruff.toml" --quiet . 2>/dev/null || true
    echo "DONE"

    echo -n "[ruff:check] $py_count files... "
    output=$(ruff check --config "$LAF_DIR/ruff.toml" . 2>&1) || {
        echo "ISSUES"
        EXIT_CODE=1
        if [[ "$VERBOSE" == true ]]; then
            echo "$output"
            echo ""
        fi
    }
    [[ $EXIT_CODE -eq 0 ]] && echo "OK"
fi

# YAML: yamllint
if has_files "*.yaml" || has_files "*.yml"; then
    check_tool yamllint
    yaml_count=$(($(count_files "*.yaml") + $(count_files "*.yml")))

    echo -n "[yamllint] $yaml_count files... "
    output=$(yamllint -c "$LAF_DIR/yamllint.yaml" . 2>&1) || {
        echo "ISSUES"
        EXIT_CODE=1
        if [[ "$VERBOSE" == true ]]; then
            echo "$output"
            echo ""
        fi
    }
    [[ -z "${output:-}" ]] && echo "OK"
fi

# HTML: curlylint
if has_files "*.html"; then
    check_tool curlylint
    html_count=$(count_files "*.html")

    echo -n "[curlylint] $html_count files... "
    output=$(curlylint --config "$LAF_DIR/curlylint.toml" . 2>&1) || {
        echo "ISSUES"
        EXIT_CODE=1
        if [[ "$VERBOSE" == true ]]; then
            echo "$output"
            echo ""
        fi
    }
    [[ $EXIT_CODE -eq 0 ]] && echo "OK"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "All checks passed"
else
    echo "Issues found (run with --verbose for details)"
fi

exit $EXIT_CODE
