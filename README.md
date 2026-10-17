# ZiggyBites Kitchen — Restaurant App

Flutter app for restaurant partners on ZiggyBites. It wraps the restaurant dashboard at [ziggybites.com/food/restaurant](https://www.ziggybites.com/food/restaurant) in a native WebView and adds loud, reliable new-order alerts that keep working when the app is in the background or closed.

| | |
|---|---|
| App name | ZiggyBites Kitchen |
| Android package / iOS bundle ID | `com.ziggybites.vendor` |
| Website loaded | `https://www.ziggybites.com/food/restaurant` |
| API base | `https://ziggybites.com/api/` |
| Version | see `version:` in `pubspec.yaml` |

## Features

- **New-order alerts:** Firebase Cloud Messaging plus a ringing alert on the high-priority channel `critical_order_alerts_v8`, using the `order_ringtone` sound. It brings the app to the front when an order arrives.
- **Background service:** `flutter_background_service` keeps alerts and ringtone playback working when the app is not open.
- **Silent channel:** non-urgent updates (status changes, accept/complete) go to a quiet channel so they don't trigger the ringtone.
- **In-app updates:** prompts for Play Store updates (`in_app_update`).
- Full-screen WebView of the restaurant dashboard (`flutter_inappwebview`)
- Native Google Sign-In, camera and gallery uploads (menu photos, documents), downloads
- Location access, plus UPI, phone, WhatsApp and maps links opened in native apps
- Splash, onboarding, offline screen, exit confirmation, light and dark theme

## Project structure

The Flutter app is a native shell. Restaurant screens are the ZiggyBites website, loaded in one `InAppWebView`. Splash, onboarding, the offline panel, and the exit dialog are the only Flutter UI.

```
lib/
├── main.dart                              # Entry: Firebase, FCM, prefs, background service, theme
├── config/
│   ├── app_config.dart                    # Name, web URL, API base, colours, notification channels
│   └── theme_config.dart                  # Light and dark Material themes
├── screens/
│   ├── splash_screen.dart                 # Flutter. Logo, then opens WebViewScreen
│   ├── onboarding_screen.dart             # Flutter. Slide deck. Not on the current launch path
│   └── webview_screen.dart                # The only WebView. Loads the restaurant website
├── widgets/
│   ├── offline_screen.dart                # Flutter overlay when the device is offline
│   └── exit_dialog.dart                   # Flutter confirm dialog on back from the root page
├── services/
│   ├── api_service.dart                   # POST /v1/fcm-tokens/mobile/save
│   └── system_overlay_service.dart        # Draw-over-apps overlay (currently unused)
└── utils/
    ├── notification_service.dart          # Foreground FCM, tray alerts, tap stream
    ├── fcm_background_handler.dart        # Pushes while the app is backgrounded or closed
    ├── new_order_notification_util.dart   # Loud new-order ringtone alerts
    ├── silent_notification_util.dart      # Quiet status updates
    ├── notification_payload_util.dart     # Title and body from an FCM payload
    ├── background_service_util.dart       # Keeps alerts alive when the app is not open
    ├── in_app_update_service.dart         # Play in-app update prompt
    ├── download_service.dart              # Saves files the website downloads
    ├── permission_handler_util.dart       # Camera, location, mic, photos, notifications
    ├── connectivity_util.dart             # Online / offline checks
    ├── prefs_util.dart                    # Token, phone, theme, onboarding flags
    └── status_bar_util.dart               # Status and navigation bar colours
```

Launch path: `SplashScreen` requests permissions, then replaces itself with `WebViewScreen`. `OnboardingScreen` still exists and also opens `WebViewScreen`, but splash does not route through it.

Ringtones are in `android/app/src/main/res/raw/` (Android), `ios/Runner/order_ringtone.mp3` (iOS) and `assets/audio/`.

> If you change a notification channel's sound or importance, bump its ID (for example `critical_order_alerts_v8` → `v9`). Android doesn't let an app change an existing channel's settings.

## WebView screens

These are website pages, not Flutter widgets. `WebViewScreen` loads `https://www.ziggybites.com/food/restaurant` and stays on any `ziggybites.com` URL. Phone, WhatsApp, email, maps, social, store, and UPI links leave the WebView and open the matching native app.

Paths below are relative to `https://www.ziggybites.com/food/restaurant`.

### Sign-in and legal

| Path | Website page | What it does |
|---|---|---|
| `/welcome` | Welcome | Entry before login |
| `/login` | Login | Phone number sign-in. The WebView reads the phone field and stores it for FCM |
| `/otp` | OTP | Verifies the restaurant OTP. The app captures the access token from `/v1/food/auth/restaurant/verify-otp` and registers the device |
| `/signup` | Signup | New restaurant registration |
| `/forgot-password` | Forgot password | Password recovery |
| `/pending-verification` | Verification pending | Shown while the restaurant account is waiting for approval |
| `/onboarding` | Onboarding | Website setup steps after signup |
| `/privacy`, `/profile/privacy` | Privacy policy | Public legal page |
| `/terms`, `/profile/terms` | Terms | Public legal page |

### Orders

| Path | Website page | What it does |
|---|---|---|
| `/` | Orders | Home after login. Live order list |
| `/orders/all` | All orders | Full order history |
| `/orders/:id` | Order details | One order. A new-order notification tap asks the page to open this order |
| `/subscriptions/:subscriptionId` | Subscription orders | Today's subscription meals for one plan |

### Menu and stock

| Path | Website page | What it does |
|---|---|---|
| `/menu-categories` | Menu categories | Category list for the menu |
| `/hub-menu/item/:id` | Item details | One dish. Camera and gallery uploads go through the native `openCamera` and `openGallery` handlers |
| `/inventory` | Inventory | Stock for menu items |

### Outlet

| Path | Website page | What it does |
|---|---|---|
| `/status` | Restaurant status | Open / closed and availability |
| `/outlet-info` | Outlet info | Outlet profile |
| `/outlet-timings` | Outlet timings | Weekly hours |
| `/outlet-timings/:day` | Day slots | Hours for one day |
| `/edit-owner` | Edit owner | Owner details |
| `/edit-cuisines` | Edit cuisines | Cuisine tags |
| `/edit-address` | Edit address | Outlet address. Location permission is granted to the WebView |
| `/manage-outlets` | Manage outlets | Switch or manage outlets |
| `/phone` | Phone numbers | Outlet phone numbers |
| `/zone-setup` | Zone setup | Delivery zones |
| `/delivery-settings` | Delivery settings | Delivery options for the outlet |
| `/rush-hour` | Rush hour | Busy-period settings |
| `/fssai` | FSSAI | Licence details |
| `/fssai/update` | Update FSSAI | Edit the licence |

### Money

| Path | Website page | What it does |
|---|---|---|
| `/hub-finance` | Finance | Payout summary |
| `/finance-details` | Finance details | Breakdown of earnings |
| `/withdrawal-history` | Withdrawal history | Past withdrawals |
| `/update-bank-details` | Bank details | Payout account |
| `/download-report` | Download report | Report files. Blob and file downloads are saved by the native download service |

### Customers and extras

| Path | Website page | What it does |
|---|---|---|
| `/ratings-reviews` | Ratings and reviews | Outlet reviews |
| `/dish-ratings` | Dish ratings | Per-dish ratings |
| `/feedback` | Feedback | Customer feedback list |
| `/share-feedback` | Share feedback | Send feedback |
| `/reservations` | Reservations | Dining reservations |
| `/promocodes` | Promocodes | Outlet offers |
| `/notifications` | Notifications | In-app notification inbox |
| `/help-centre/support` | Support | Help-centre tickets |
| `/explore` | Explore | Extra tools |
| `/hyperpure` | Hyperpure | Supplies page |

### What the WebView adds around those pages

- **Session.** After OTP login the access token is saved natively and written back into the page's `localStorage` (`accessToken`, `token`, `auth_token`).
- **Google sign-in.** The page can call `nativeGoogleSignIn`. The app returns the Google id token, email, and name.
- **Photos.** `openCamera` and `openGallery` return a base64 JPEG for menu and document uploads.
- **New-order tap.** The app calls `openOrderDetail` (and the same family of functions) or dispatches `flutterNewOrderTap` with the order id.
- **Receipts.** Blob URLs created by the page are captured and saved as files.
- **Payments.** Razorpay UPI choices and `upi` / PhonePe / Paytm / GPay links open the payment app.
- **Offline.** If the device has no network, the Flutter offline panel covers the WebView until the page can reload.

## Getting started

Requirements: Flutter (stable), Xcode for iOS builds, Android Studio or the Android SDK for Android builds.

```bash
flutter pub get
flutter run
```

Firebase is already configured for project `ziggybites-79bfc`:
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

To test order alerts, send a data push from the backend or the Firebase console. Check it with the app in the foreground, in the background, and closed.

## Release builds and signing

Signing keys are **not** stored in this repo. The release build reads them from a folder next to the repo:

```
ZiggyBites/
├── Ziggybites-restaurant-apk/   # this repo
└── signing-keys/
    └── restaurant/
        ├── key.properties       # storePassword, keyPassword, keyAlias, storeFile
        └── dardecomer.jks
```

To keep the keys elsewhere, set `ZIGGYBITES_SIGNING_DIR` to the folder that holds `key.properties` and the keystore.

```bash
flutter build appbundle --release   # Play Store
flutter build apk --release
flutter build ipa --release         # iOS
```

Release builds use R8 minification. The keep rules in `android/app/proguard-rules.pro` stop the ringtone, background service and notifications from breaking in release builds. Keep them when adding plugins.

## Security notes

- Never commit `key.properties`, `*.jks` or `*.keystore`; they are listed in `.gitignore`.
- Automatic VS Code tasks are turned off in `.vscode/settings.json`. Don't add tasks that run on folder open.
- The app only allows HTTPS traffic: cleartext is disabled on Android, and iOS uses the default App Transport Security.
