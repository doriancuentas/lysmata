# Lysmata

![Cleaner Shrimp](https://upload.wikimedia.org/wikipedia/commons/0/07/Cleaner_Shrimp_on_zoanthus_macro.jpg)

*Like a cleaner shrimp keeps fish healthy, Lysmata keeps your code clean.*

---

## What

Project-agnostic code quality script. Drop into any project for consistent linting, formatting, and security scanning.

**Offline-first**: No internet required. All tools work locally.

## Install

```bash
pip install -r .laf/requirements.txt
```

## Usage

```bash
./check.sh           # Summary output
./check.sh --verbose # Detailed errors
```

## Tools

| File Type | What it does |
|-----------|--------------|
| `*.py` | ruff (lint + format + security) |
| `*.yaml/*.yml` | yamllint |
| `*.html` | curlylint |
| `requirements.txt` | pip-audit (vulnerabilities) |

## Config

All configuration lives in `.laf/`:

```
.laf/
├── requirements.txt   # Tool dependencies
├── ruff.toml          # Python lint + format + security
├── yamllint.yaml      # YAML lint rules
├── curlylint.toml     # HTML template lint rules
└── templates/         # Project-specific stack docs
    └── bumerange/     # Django + Vue + PostGIS
```

## Exit Codes

- `0` - All checks passed
- `1` - Issues found (run `--verbose` for details)

## Philosophy

- **Offline-first**: No internet required
- **Fail-fast**: Missing tool = immediate exit
- **One script**: Lint + format + security in one command
- **Summary output**: Clean CI logs; `--verbose` for details
- **Project-agnostic**: Auto-detects file types

## Changelog

- **0.3.0** - TypeScript/JavaScript support (eslint, prettier, security scanning, tsc)
- **0.2.0** - Merged scripts into single check.sh, replaced semgrep with ruff for security
- **0.1.0** - Initial release with Python, YAML, HTML support

See [CHANGELOG.md](CHANGELOG.md) for full details.

## License

MIT
