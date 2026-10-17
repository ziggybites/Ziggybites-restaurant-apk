# ZiggyBites Kitchen — Project Structure

| Field     | Value                                        |
| --------- | -------------------------------------------- |
| Package   | `webview_master_app`                         |
| App name  | ZiggyBites Kitchen                           |
| Bundle ID | `com.ziggybites.vendor`                      |
| Version   | `2.1.18+19`                                  |
| Site      | `https://www.ziggybites.com/food/restaurant` |

## Summary

Flutter is only the shell. The restaurant dashboard is the website inside one WebView (`WebViewScreen`). Splash opens that WebView. Orders, login, menu, finance, and outlet pages are website routes, not Flutter screens.

## Flutter modules

| Module                           | WebView | Role                                |
| -------------------------------- | ------- | ----------------------------------- |
| `main.dart`                      | No      | App start, then splash              |
| `config/`                        | No      | Name, URL, theme, alerts            |
| `screens/splash_screen.dart`     | No      | Logo, then opens WebView            |
| `screens/onboarding_screen.dart` | No      | Slides, not used on launch          |
| `screens/webview_screen.dart`    | Yes     | Loads the whole dashboard           |
| `widgets/offline_screen.dart`    | No      | Offline overlay                     |
| `widgets/exit_dialog.dart`       | No      | Exit confirm                        |
| `services/`                      | No      | FCM token save                      |
| `utils/`                         | No      | Push, downloads, permissions, prefs |

## Website modules

Base path: `https://www.ziggybites.com/food/restaurant`

| Module               | WebView | Path                           |
| -------------------- | ------- | ------------------------------ |
| Welcome              | Yes     | /welcome                       |
| Login                | Yes     | /login                         |
| OTP                  | Yes     | /otp                           |
| Signup               | Yes     | /signup                        |
| Forgot password      | Yes     | /forgot-password               |
| Verification pending | Yes     | /pending-verification          |
| Onboarding           | Yes     | /onboarding                    |
| Privacy              | Yes     | /privacy                       |
| Terms                | Yes     | /terms                         |
| Orders               | Yes     | /                              |
| All orders           | Yes     | /orders/all                    |
| Order details        | Yes     | /orders/:id                    |
| Subscription orders  | Yes     | /subscriptions/:subscriptionId |
| Menu categories      | Yes     | /menu-categories               |
| Item details         | Yes     | /hub-menu/item/:id             |
| Inventory            | Yes     | /inventory                     |
| Status               | Yes     | /status                        |
| Outlet info          | Yes     | /outlet-info                   |
| Outlet timings       | Yes     | /outlet-timings                |
| Edit owner           | Yes     | /edit-owner                    |
| Edit cuisines        | Yes     | /edit-cuisines                 |
| Edit address         | Yes     | /edit-address                  |
| Manage outlets       | Yes     | /manage-outlets                |
| Phone                | Yes     | /phone                         |
| Zone setup           | Yes     | /zone-setup                    |
| Delivery settings    | Yes     | /delivery-settings             |
| Rush hour            | Yes     | /rush-hour                     |
| FSSAI                | Yes     | /fssai                         |
| Finance              | Yes     | /hub-finance                   |
| Finance details      | Yes     | /finance-details               |
| Withdrawal history   | Yes     | /withdrawal-history            |
| Bank details         | Yes     | /update-bank-details           |
| Reports              | Yes     | /download-report               |
| Reviews              | Yes     | /ratings-reviews               |
| Dish ratings         | Yes     | /dish-ratings                  |
| Feedback             | Yes     | /feedback                      |
| Share feedback       | Yes     | /share-feedback                |
| Reservations         | Yes     | /reservations                  |
| Promocodes           | Yes     | /promocodes                    |
| Notifications        | Yes     | /notifications                 |
| Support              | Yes     | /help-centre/support           |
| Explore              | Yes     | /explore                       |
| Hyperpure            | Yes     | /hyperpure                     |
