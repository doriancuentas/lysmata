# Changelog

## [0.3.0] - 2025-01-15

### Added
- TypeScript/JavaScript support with eslint + prettier
- Security scanning for TS/JS via eslint-plugin-security
- Type checking with tsc --noEmit
- Auto-detection of pnpm/npm package manager

## [0.2.0] - 2024-12-22

### Changed
- Merged lint_and_format.sh + security_check.sh into single check.sh
- Replaced semgrep with ruff for Python security (offline, faster)

## [0.1.0] - 2024-12-03

### Added
- Initial release with lint_and_format.sh and security_check.sh
- Python: ruff for linting and formatting
- YAML: yamllint
- HTML: curlylint
- Dependencies: pip-audit for vulnerability scanning
- .laf/ directory with shared configs
