#!/usr/bin/env bash
# Lint, format, and security scan. Run with --help for usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAF_DIR="$SCRIPT_DIR/.laf"
VERBOSE=false
EXIT_CODE=0

show_usage() {
    cat << 'EOF'
Lysmata - Code Quality Check

Usage: ./check.sh [--verbose] [--help]

Runs all checks (offline, no internet required):
  *.ts/*.tsx/*.js   -> eslint + prettier (lint + format + security)
  *.py              -> ruff (lint + format + security)
  *.yaml/*.yml      -> yamllint
  *.html            -> curlylint
  requirements.txt  -> pip-audit (dependency vulnerabilities)

Note: TS/JS security requires eslint-plugin-security in your project.

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

echo "Lysmata - Code Quality Check"
echo "============================"
echo ""

# TypeScript/JavaScript: ESLint + Prettier (with security)
if has_files "*.ts" || has_files "*.tsx" || has_files "*.js"; then
    ts_count=$(($(count_files "*.ts") + $(count_files "*.tsx") + $(count_files "*.js")))

    # Check for package manager (pnpm preferred, fallback to npm)
    if command -v pnpm &>/dev/null && [[ -f "pnpm-lock.yaml" ]]; then
        PM="pnpm"
    elif command -v npm &>/dev/null; then
        PM="npm"
    else
        echo "[ts/js] Skipping - no package manager found"
        PM=""
    fi

    if [[ -n "$PM" ]]; then
        # Format with prettier (if available)
        if $PM exec prettier --version &>/dev/null 2>&1; then
            echo -n "[prettier] $ts_count files... "
            $PM exec prettier --write "**/*.{ts,tsx,js,json}" --log-level=error 2>/dev/null || true
            echo "DONE"
        fi

        # Lint + Fix with eslint (if available)
        if $PM exec eslint --version &>/dev/null 2>&1; then
            echo -n "[eslint:fix] $ts_count files... "
            $PM exec eslint --fix . --quiet 2>/dev/null || true
            echo "DONE"

            # Check (includes security rules if eslint-plugin-security installed)
            echo -n "[eslint:check] $ts_count files... "
            if [[ "$VERBOSE" == true ]]; then
                output=$($PM exec eslint . 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                    echo "$output"
                    echo ""
                }
            else
                output=$($PM exec eslint . --quiet 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                }
            fi
            [[ $EXIT_CODE -eq 0 ]] && echo "OK"
        fi

        # Type check (if tsc available)
        if $PM exec tsc --version &>/dev/null 2>&1; then
            echo -n "[tsc] type checking... "
            if [[ "$VERBOSE" == true ]]; then
                output=$($PM exec tsc --noEmit 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                    echo "$output"
                    echo ""
                }
            else
                output=$($PM exec tsc --noEmit 2>&1) || {
                    echo "ISSUES"
                    EXIT_CODE=1
                }
            fi
            [[ $EXIT_CODE -eq 0 ]] && echo "OK"
        fi
    fi
fi

# Python: ruff (lint + format + security)
if has_files "*.py"; then
    check_tool ruff
    py_count=$(count_files "*.py")

    # Fix
    echo -n "[ruff:fix] $py_count files... "
    ruff check --config "$LAF_DIR/ruff.toml" --fix --quiet . 2>/dev/null || true
    echo "DONE"

    # Format
    echo -n "[ruff:format] $py_count files... "
    ruff format --config "$LAF_DIR/ruff.toml" --quiet . 2>/dev/null || true
    echo "DONE"

    # Check (includes security S rules)
    echo -n "[ruff:check] $py_count files... "
    if [[ "$VERBOSE" == true ]]; then
        output=$(ruff check --config "$LAF_DIR/ruff.toml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            echo "$output"
            echo ""
        }
    else
        output=$(ruff check --config "$LAF_DIR/ruff.toml" --quiet . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
        }
    fi
    [[ $EXIT_CODE -eq 0 ]] && echo "OK"
fi

# YAML: yamllint
if has_files "*.yaml" || has_files "*.yml"; then
    check_tool yamllint
    yaml_count=$(($(count_files "*.yaml") + $(count_files "*.yml")))

    echo -n "[yamllint] $yaml_count files... "
    if [[ "$VERBOSE" == true ]]; then
        output=$(yamllint -c "$LAF_DIR/yamllint.yaml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            echo "$output"
            echo ""
        }
    else
        output=$(yamllint -c "$LAF_DIR/yamllint.yaml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
        }
    fi
    [[ -z "${output:-}" ]] && echo "OK"
fi

# HTML: curlylint
if has_files "*.html"; then
    check_tool curlylint
    html_count=$(count_files "*.html")

    echo -n "[curlylint] $html_count files... "
    if [[ "$VERBOSE" == true ]]; then
        output=$(curlylint --config "$LAF_DIR/curlylint.toml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            echo "$output"
            echo ""
        }
    else
        output=$(curlylint --config "$LAF_DIR/curlylint.toml" . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
        }
    fi
    [[ $EXIT_CODE -eq 0 ]] && echo "OK"
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

    for req_file in "${REQ_FILES[@]}"; do
        echo -n "[pip-audit] $req_file... "
        if [[ "$VERBOSE" == true ]]; then
            output=$(pip-audit -r "$req_file" 2>&1) || {
                echo "VULNERABILITIES"
                EXIT_CODE=1
                echo "$output"
                echo ""
            }
        else
            output=$(pip-audit -r "$req_file" --progress-spinner=off 2>&1) || {
                echo "VULNERABILITIES"
                EXIT_CODE=1
            }
        fi
        [[ $? -eq 0 ]] && echo "OK"
    done
elif [[ -f "pyproject.toml" ]]; then
    check_tool pip-audit
    echo -n "[pip-audit] pyproject.toml... "
    if [[ "$VERBOSE" == true ]]; then
        output=$(pip-audit 2>&1) || {
            echo "VULNERABILITIES"
            EXIT_CODE=1
            echo "$output"
            echo ""
        }
    else
        output=$(pip-audit --progress-spinner=off 2>&1) || {
            echo "VULNERABILITIES"
            EXIT_CODE=1
        }
    fi
    [[ $? -eq 0 ]] && echo "OK"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "All checks passed"
else
    echo "Issues found (run with --verbose for details)"
fi

exit $EXIT_CODE
