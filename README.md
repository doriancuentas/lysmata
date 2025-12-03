# Lysmata

![Cleaner Shrimp](https://upload.wikimedia.org/wikipedia/commons/0/07/Cleaner_Shrimp_on_zoanthus_macro.jpg)

*Like a cleaner shrimp keeps fish healthy, Lysmata keeps your code clean.*

---

## What

Project-agnostic linting, formatting, and security scanning scripts. Drop into any project for consistent code quality.

## Install

```bash
pip install -r .laf/requirements.txt
```

## Usage

### Lint & Format

```bash
./lint_and_format.sh           # Summary output
./lint_and_format.sh --verbose # Detailed errors
```

### Security Check

```bash
./security_check.sh           # Summary output
./security_check.sh --verbose # Detailed findings
```

## Tools

| File Type | Lint Tool | Security Tool |
|-----------|-----------|---------------|
| `*.py` | ruff | bandit |
| `*.yaml/*.yml` | yamllint | - |
| `*.html` | curlylint | - |
| `requirements.txt` | - | safety |

## Config

All configuration lives in `.laf/`:

```
.laf/
├── requirements.txt   # Tool dependencies
├── ruff.toml          # Python lint + format
├── bandit.yaml        # Python security rules
├── yamllint.yaml      # YAML lint rules
└── curlylint.toml     # HTML template lint rules
```

## Exit Codes

- `0` - All checks passed
- `1` - Issues found (run `--verbose` for details)

## Philosophy

- **Fail-fast**: Missing tool = immediate exit with install instructions
- **Strict by default**: One config, no "levels"
- **Summary output**: Clean CI logs; `--verbose` for debugging
- **Project-agnostic**: Auto-detects file types, no hardcoded paths

## License

MIT
