# Dip Report (MarineCheck) - Project Documentation

## Overview
Dip Report is a Flutter-based application for open sea swimmers in Ireland. It provides high-accuracy coastal weather, tide data, wave/swell information, community photo sharing, and a custom **Roughness Index** to help swimmers assess conditions at a glance.

**Live at**: https://dipreport.com

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter (Dart) — Android, iOS, Web |
| **Backend** | Phoenix / Elixir with Ecto |
| **Database** | PostgreSQL (`dipguide_backend_prod`) |
| **Web Server** | Nginx (reverse proxy, SSL, CORS proxy) |
| **Hosting** | `euro` server (`46.62.230.130`), Ubuntu Linux |
| **Auth** | Ueberauth (Google OAuth + Magic Link email) |
| **Storage** | Persistent uploads at `/var/lib/dipguide_backend/uploads` |

### Data APIs
- **Met Eireann**: Professional Irish weather forecasts (XML/Direct)
- **Marine Institute**: Real-time and predicted tide data
- **Open-Meteo**: Global wave/swell models, geocoding, and weather snapshots for share previews

### Key Dependencies
- `image_picker` — Camera/gallery photo capture (with web fallback via `dart:html`)
- `share_plus` — Native share sheet
- `flutter_secure_storage` — Auth token persistence
- `webview_flutter` — Webcam display on native platforms
- `dio` — HTTP client with multipart upload support
- `rsvg-convert` (server) — SVG to PNG conversion for social media preview images

---

## Key Features

### 1. Weather Forecasting
- **Marine Service**: Merges parallel API calls from Met Eireann, Marine Institute, and Open-Meteo into a single 7-day timeline
- **Roughness Index**: Safety algorithm weighting wave height, wind speed, and swell direction (0=Calm to 100=Unsafe)
- **Fallback System**: Switches to Open-Meteo when Met Eireann data is unavailable (marked with `*`)
- **7-Day Navigation**: Swipe-able and arrow-navigated daily forecasts
- **Next 2 Hours**: Snapshot summary card for immediate decision making

### 2. Community Photo Posts
- Users can post photos with comments, associated with a weather location
- Photos are compressed client-side (max 1400px, JPEG 82%) before upload
- Server stores images with UUID-based file paths
- All posts are public — visible to other swimmers sorted by proximity
- Post owners can delete their own posts
- Deep linking: shared URLs navigate directly to the specific post

### 3. Social Sharing ("Share Dip Report")
- Unified share experience across the app (main screen, detail sheet, photo posts)
- **Composite preview images**: Backend generates 1200x630 PNG images containing:
  - Weather data row (temperature, wind, waves, roughness badge)
  - User's photo (center-cropped into landscape format) when available
  - Location name, date, and dipreport.com branding
- **OG/Twitter meta tags**: Rich link previews on WhatsApp, iMessage, social media
- **Short URLs**: `/s/<8-char-uuid>` redirects to full share page
- Share page is fully clickable — takes user to the main forecast screen
- SVG-to-PNG conversion via `rsvg-convert` (WhatsApp doesn't support SVG for `og:image`)

### 4. Webcam Integration
- Live streams for Forty Foot and Tramore
- Platform-conditional rendering:
  - **Web**: Direct ipcamlive iframe embed (Forty Foot), Nginx-proxied MJPEG (Tramore)
  - **Native**: `webview_flutter` with Nginx-proxied URLs for both

### 5. Android Home Screen Widget
- Multi-widget support — each tracks a different location
- Native Kotlin configuration activity (`WidgetConfigurationActivity`)
- Custom XML layout (`widget_layout.xml`)

### 6. Performance & UX
- **Optimistic cache loading**: Displays cached forecast data instantly on startup, refreshes from API in background
- **Dark theme**: Body background set in `web/index.html` to prevent white flash before Flutter loads
- Loading spinner shown while fetching fresh data

---

## Backend Architecture

### Phoenix Application (`dipguide_backend/`)

#### Database Schema (PostgreSQL)
- **`users`** — Authentication records (Ueberauth)
- **`location_posts`** — Community posts (`id` as UUID, `user_id`, `location_name`, `lat`, `lon`, `comment`, `visibility` default "public", `forecast_time`, timestamps)
- **`location_post_images`** — Photo metadata (`id`, `post_id`, `file_key`, `content_type`, timestamps)

#### Key Modules
| Module | Purpose |
|--------|---------|
| `DipguideBackend.Community` | Business logic for posts (CRUD, haversine proximity queries, short ID lookup) |
| `DipguideBackend.WeatherShare` | Fetches weather snapshots from Open-Meteo for share previews |
| `DipguideBackendWeb.ShareController` | Generates HTML share pages, composite SVG/PNG preview images, short URL redirects |
| `DipguideBackendWeb.ShareView` | View helpers for formatting weather data in templates and SVG generation |
| `DipguideBackendWeb.Plugs.UploadsStatic` | Serves user-uploaded files from runtime-configured directory |
| `DipguideBackendWeb.AuthController` | OAuth and magic link authentication flows with `return_to` redirect support |

#### API Routes
- `POST /api/posts` — Create post (multipart upload, authenticated)
- `GET /api/posts/:id` — Get single post
- `DELETE /api/posts/:id` — Delete own post (authenticated)
- `GET /api/posts/public/location` — List posts by location
- `GET /api/posts/public/nearby` — List posts by proximity (haversine)
- `GET /share/posts/:id` — Share page with OG meta tags
- `GET /share/posts/:id/preview.png` — Composite preview image (weather + photo)
- `GET /share/forecast` — Forecast share page
- `GET /share/forecast/preview.png` — Forecast-only preview image
- `GET /s/:short_id` — Short URL redirect

### Authentication
- **Google OAuth**: Via Ueberauth with `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`
- **Magic Link**: Email-based passwordless login via SMTP
- **Token persistence**: `flutter_secure_storage` stores auth token; only cleared on explicit 401/403 (not transient network errors)
- **Deep link support**: `return_to` parameter preserves user intent through auth flow (e.g., auto-opens compose dialog after login)

### Nginx Configuration (`dipreport.nginx`)
- SSL via Let's Encrypt
- `client_max_body_size 25M` for photo uploads
- Reverse proxy to Phoenix on `localhost:4040`
- `/uploads/` — Proxied to Phoenix for user-uploaded files
- `/share/` — Proxied to Phoenix for share pages
- `/s/` — Proxied to Phoenix for short URL redirects
- `/webcams/fortyfoot` — Proxied to ipcamlive (CORS bypass for native)
- `/webcams/tramore.mjpg` — Proxied to Tramore MJPEG stream

### File Storage
- Upload directory: `/var/lib/dipguide_backend/uploads` (persistent, outside deploy rsync path)
- `UPLOAD_DIR` environment variable injected via systemd service
- UUID-based file keys prevent conflicts

---

## Infrastructure & Deployment

### Server Access
- **Host**: `euro` (`46.62.230.130`)
- **SSH**: `ssh euro` (key-based)
- **Backend Service**: `dipguide_backend` (systemd)
- **Backend Path**: `/opt/dipguide_backend`
- **Backend Port**: `4040` (internal)
- **Web Root**: `/var/www/dipreport.com`

### Environment Variables (systemd service)
| Variable | Purpose |
|----------|---------|
| `SECRET_KEY_BASE` | Phoenix secret |
| `DATABASE_URL` | PostgreSQL connection string |
| `PHX_HOST` | `dipreport.com` (link generation) |
| `UPLOAD_DIR` | `/var/lib/dipguide_backend/uploads` |
| `GOOGLE_CLIENT_ID` | Google OAuth |
| `GOOGLE_CLIENT_SECRET` | Google OAuth |
| `SMTP_SERVER` | Magic link email |
| `SMTP_USERNAME` | Magic link email |
| `SMTP_PASSWORD` | Magic link email |
| `MAIL_FROM` | Magic link email |

### Deployment Scripts

#### Full Deployment (`deploy_full.sh`)
Handles: Database setup, Phoenix backend build/deploy, systemd configuration, migrations, Flutter web build/deploy, Nginx configuration.

```bash
bash deploy_full.sh
```

#### Web-Only Deployment (`deploy_web.sh`)
Faster deployment for frontend-only changes (Flutter build + rsync).

```bash
bash deploy_web.sh
```

### Build & Release

#### Flutter Web
```bash
/home/david/flutter/bin/flutter build web --release
```

#### Android APK
```bash
/home/david/flutter/bin/flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

#### GitHub Releases
```bash
gh release create v1.x.x \
  --repo davidcotter/marine-check-flutter \
  --title "v1.x.x Description" \
  --notes "Release notes." \
  ./build/app/outputs/flutter-apk/app-release.apk
```

---

## Project Structure (Key Files)

```
lib/
├── main.dart                          # App entry, deep linking, cache-first loading
├── models/
│   ├── marine_data.dart               # Weather/forecast data models
│   ├── location_post.dart             # Community post models
│   └── notification_schedule.dart     # Notification scheduling
├── screens/
│   ├── location_posts_screen.dart     # Community posts feed + compose dialog
│   ├── login_screen.dart              # Auth screen with return_to support
│   └── webcam_screen.dart             # Platform-conditional webcam display
├── services/
│   ├── marine_service.dart            # Core weather data aggregation
│   ├── auth_service.dart              # Token management, login persistence
│   ├── location_post_service.dart     # Post CRUD + share URL builder
│   ├── location_service.dart          # Saved locations management
│   ├── forecast_cache.dart            # Optimistic cache for instant loading
│   └── ...                            # Other services (tide, pollution, etc.)
├── widgets/
│   ├── share_modal.dart               # Unified "Share Dip Report" bottom sheet
│   ├── location_post_card.dart        # Post display card with share/delete
│   ├── hour_detail_sheet.dart         # Detailed hourly forecast sheet
│   └── forecast_summary_card.dart     # Weather summary for share preview
└── utils/
    ├── web_image_picker_web.dart       # Web-specific image picker (dart:html)
    └── web_image_picker_stub.dart      # Stub for non-web platforms

dipguide_backend/
├── lib/
│   ├── dipguide_backend/
│   │   ├── community.ex               # Post business logic + haversine queries
│   │   └── weather_share.ex           # Open-Meteo weather snapshots
│   └── dipguide_backend_web/
│       ├── controllers/
│       │   ├── share_controller.ex     # Share pages + composite PNG generation
│       │   ├── share_html/post.html.heex  # Share page template
│       │   └── api/location_post_controller.ex  # REST API for posts
│       ├── views/share_view.ex         # Weather formatting helpers
│       └── router.ex                   # All routes
├── priv/repo/migrations/              # Ecto migrations
└── config/runtime.exs                 # Production runtime config

deploy_full.sh          # Full stack deployment
deploy_web.sh           # Frontend-only deployment
dipreport.nginx         # Nginx config for dipreport.com
dipguide_backend.service  # Systemd service template
```

---

## Troubleshooting

### WhatsApp Share Previews
- WhatsApp aggressively caches link previews — always test with a **new** share URL
- Preview images must be PNG (WhatsApp ignores SVG for `og:image`)
- Images must be served over HTTPS with correct `Content-Type: image/png`
- `rsvg-convert` (from `librsvg2-bin`) must be installed on the server

### Login Not Persisting
- Auth token is stored in `flutter_secure_storage`
- Token is only cleared on explicit 401/403 from server, not transient network errors
- Check `AuthService.init()` and `fetchProfile()` for token validation logic

### Webcams Not Working on Web
- Forty Foot uses direct ipcamlive iframe embed on web (not proxied)
- Tramore uses Nginx-proxied MJPEG stream
- If Nginx proxy fails, check `location /webcams/` blocks in `dipreport.nginx`

### White Flash on Web Load
- `web/index.html` sets `background-color: #0f172a` on body to match dark theme
- Cache-first loading shows cached data instantly before API refresh
