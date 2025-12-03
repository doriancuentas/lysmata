#!/usr/bin/env bash
# Security scan codebase. Run with --help for usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAF_DIR="$SCRIPT_DIR/.laf"
VERBOSE=false
EXIT_CODE=0

show_usage() {
    cat << 'EOF'
Lysmata - Security Check

Usage: ./security_check.sh [--verbose] [--help]

Runs security checks (offline, no internet required):
  *.py              -> ruff with S rules (flake8-bandit)
  requirements.txt  -> pip-audit (dependency vulnerabilities)

Options:
  --verbose   Show detailed findings (default: summary only)
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

echo "Lysmata - Security Check"
echo "========================"
echo ""

# Python: ruff with security rules (S prefix = flake8-bandit)
if has_files "*.py"; then
    check_tool ruff
    py_count=$(count_files "*.py")

    echo -n "[ruff:security] $py_count files... "

    if [[ "$VERBOSE" == true ]]; then
        # Show only security rules (S prefix)
        output=$(ruff check --config "$LAF_DIR/ruff.toml" --select=S . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
            echo "$output"
            echo ""
        }
    else
        output=$(ruff check --config "$LAF_DIR/ruff.toml" --select=S --quiet . 2>&1) || {
            echo "ISSUES"
            EXIT_CODE=1
        }
    fi
    [[ $EXIT_CODE -eq 0 ]] && echo "OK"
else
    echo "[ruff:security] No Python files found"
fi

# Dependencies: pip-audit
REQ_FILES=()

# Find requirements files
while IFS= read -r -d '' file; do
    REQ_FILES+=("$file")
done < <(find . -maxdepth 2 -name "requirements*.txt" \
    -not -path "./.venv/*" \
    -not -path "./venv/*" \
    -not -path "./.laf/*" \
    -print0 2>/dev/null)

# Remove duplicates and sort
if [[ ${#REQ_FILES[@]} -gt 0 ]]; then
    REQ_FILES=($(printf "%s\n" "${REQ_FILES[@]}" | sort -u))
fi

if [[ ${#REQ_FILES[@]} -gt 0 ]]; then
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
else
    echo "[pip-audit] Warning: No requirements.txt or pyproject.toml found"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Security scan passed"
else
    echo "Security issues found (run with --verbose for details)"
fi

exit $EXIT_CODE
