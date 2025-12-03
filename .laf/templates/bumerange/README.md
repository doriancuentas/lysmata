# Bumerange

Delivery/logistics platform with geospatial capabilities.

## Tech Stack

### Backend

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | 3.11 | Runtime |
| Django | 4.2.9 | Web framework |
| PostgreSQL + PostGIS | 15-3.3 | Database with geospatial |
| Django REST Framework | 3.14.0 | API endpoints |
| inertia-django | - | Server-driven SPA |
| django-leaflet | - | Map integration |
| django-unfold | - | Admin UI |
| django-cors-headers | - | CORS handling |
| bcrypt | - | Password hashing |
| APScheduler | - | Background jobs |
| sentry-sdk | - | Error tracking |
| gunicorn | - | Production WSGI |

### Frontend

| Component | Version | Purpose |
|-----------|---------|---------|
| Vue | 3.3.11 | UI framework |
| TypeScript | - | Type safety |
| @inertiajs/vue3 | - | Server-driven routing |
| Tailwind CSS | 3.4.0 | Styling |
| Vite | 5.0.10 | Build tool |
| Vue I18n | - | i18n (pt-BR default) |
| axios | - | HTTP client |

### Infrastructure

| Component | Purpose |
|-----------|---------|
| Docker + Compose | Containerization |
| Nginx | Reverse proxy + rate limiting |
| GitHub Actions | CI/CD |
| GitHub Container Registry | Docker images |
| Ansible | Server config |
| Ubuntu + UFW + fail2ban | Production OS + security |

### Development

| Tool | Purpose |
|------|---------|
| Nix (IDX) | Reproducible dev environment |
| GDAL/GEOS/PROJ | Geospatial libraries |
| pytest + coverage | Testing |
| Ruff | Linting |
| MyPy | Type checking |
| Pre-commit hooks | Code quality gates |

## Architecture

- **Pattern**: Monolithic Django with modular design
- **UI**: Server-driven via Inertia.js
- **Auth**: Session-based (staff), PIN-based (drivers)
- **Geo**: Full PostGIS support for delivery routing

## Lint/Security Config

Copy `.laf/` configs to project root. No changes needed for standard Django projects.

For Django-specific exclusions, `semgrep.yaml` already excludes:
- `**/migrations/` (auto-generated)
- `**/tests/` (intentional unsafe patterns)
