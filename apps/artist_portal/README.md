# Artist Portal (e.g. artists.zalmanim.com)

A **separate**, label-branded Flutter app for artists. Deploy it at **artists.zalmanim.com** (or your label subdomain). It uses the same backend API as the admin app but has its own UI and branding.

**Login:** Artists sign in with their **artist email + password** stored in the **artists** table (not the admin users table). An admin must set each artist's portal password first (Artists tab → "Set portal password").

## Features

- Artist sign-in only (rejects admin/manager accounts with a clear message)
- **My profile** – update display name, full name, website, notes
- **Send demo** – submit a demo with optional message and file
- **My demos** – list of your demo submissions and status
- **Upload new music** – upload a release (track title + file)
- **My releases** – list of your releases and status
- **My media** – personal media folder (upload, download, delete)
- **Tasks** – system tasks related to your account
- Sign out

## Label branding

Edit `lib/core/app_config.dart` or use build arguments to customize:

| Setting | Env / `--dart-define` | Default | Description |
|--------|----------------------|---------|-------------|
| API URL | `API_BASE_URL` | `http://localhost:8000/` | Backend API base |
| Label name | `LABEL_NAME` | `Artist Portal` | Shown in app bar and login |
| Primary color | `PRIMARY_COLOR` | `1B7A5E` | Hex color (no `#`) for theme |
| Logo URL | `LOGO_URL` | (empty) | Optional logo image URL |

Example build with custom label:

```bash
flutter build web \
  --dart-define=API_BASE_URL=https://api.yourlabel.com/ \
  --dart-define=LABEL_NAME="Zalmanim Records" \
  --dart-define=PRIMARY_COLOR=2C1810
```

## Run locally

```bash
cd apps/artist_portal
flutter pub get
flutter run -d chrome
```

Ensure the backend is running (e.g. `http://localhost:8000`) and that you have an artist user (role `artist` linked to an artist record).

## Deploy

- **Web:** Build with `flutter build web` and serve the `build/web` folder (e.g. on a subdomain like `artists.yourlabel.com`).
- **Mobile:** Build with `flutter build apk` or `flutter build ios` and distribute as a separate app from the admin app.
