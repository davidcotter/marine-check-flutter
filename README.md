    # Dip Report

A Flutter app for open sea swimmers in Ireland. Provides coastal weather, tide data, wave/swell info, community photo sharing, and a custom **Roughness Index** to help assess swimming conditions at a glance.

**Live at**: https://dipreport.com

## Tech Stack

- **Frontend**: Flutter (Dart) — Android, iOS, Web
- **Backend**: Phoenix / Elixir with Ecto
- **Database**: PostgreSQL
- **Web Server**: Nginx (reverse proxy, SSL)
- **Auth**: Ueberauth (Google OAuth + Magic Link email)

## Key Features

- 7-day coastal weather forecasts (Met Éireann, Marine Institute, Open-Meteo)
- Roughness Index — safety score weighting wave height, wind, and swell direction
- Community photo posts tied to swim locations
- Social sharing with composite OG preview images
- Live webcam feeds (Forty Foot, Tramore)
- Android home screen widget

## Project Structure

```
lib/                        # Flutter app
├── main.dart
├── models/
├── screens/
├── services/
├── widgets/
└── utils/

dipguide_backend/           # Phoenix/Elixir backend
├── lib/
├── config/
└── priv/repo/migrations/

deploy_full.sh              # Full stack deployment
deploy_web.sh               # Frontend-only deployment
dipreport.nginx             # Nginx config
```

## Deployment

```bash
# Full stack
bash deploy_full.sh

# Frontend only
bash deploy_web.sh
```

## Build

```bash
# Flutter web
flutter build web --release

# Android APK
flutter build apk --release
```

See [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) for full documentation.
