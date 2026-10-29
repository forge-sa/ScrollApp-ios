# ScrollApp for iOS

iPhone port of [ScrollApp](https://github.com/forge-sa/ScrollApp-android): one vertical feed mixing **YouTube Shorts, Instagram Reels
and TikToks**, with autoscroll, ad/filler skipping, like and repost buttons, and scrolling statistics.

> **Status:** written on Linux, where iOS apps can't be built. All Swift files pass a Swift 5.10 syntax
> check, but the project has not been compiled against the iOS SDK yet, so the first build in Xcode
> may need small fixes.

## Build and install

Needs a Mac with **Xcode 16 or newer** and an iPhone on **iOS 17+**.

1. Open `ScrollApp.xcodeproj`.
2. Select the **ScrollApp** target → **Signing & Capabilities** → choose your **Team** (a free Apple ID
   works). If Xcode says the bundle identifier is taken, change `dev.wardar.scrollapp` to anything unique.
3. Connect the iPhone, turn on **Developer Mode** (Settings → Privacy & Security), and press **Run**.

With a free Apple ID the app stops opening after 7 days; run it from Xcode again to renew it.
A paid developer account makes that one year.

If Xcode can't open the project, regenerate it: `brew install xcodegen && xcodegen` (uses `project.yml`).

## Using it

Same as the Android app: swipe up/down to move through all three sources, the heart likes, the
repost button uses the site's repost or opens the share sheet, the arrow toggles autoscroll, and the
chart button shows statistics (time scrolled; numbers of shorts, reels and TikToks; ads skipped;
per-day chart). On first launch, log in to each source from the Settings screen.

## How it differs from Android

iOS gives apps no way to send a web page a real touch, so where the Android app swipes and taps,
this one drives the sites from script:

| | YouTube | Instagram | TikTok |
|---|---|---|---|
| Next video | site's own "Next video" button | feed scroller | TikTok's Swiper |
| Previous video | may land on a neighbouring short | exact | exact |
| Like / repost | clicks the site's button | same | same |

These script paths were checked against the live sites (in Android's WebView, which gets the same
pages). Ad networks are blocked with a WebKit content rule list; Instagram and TikTok ads are
recognised by their "Sponsored" label and skipped, as on Android.

## Project layout

- `ScrollApp/Feed/` – the unified feed: one `WKWebView` per source (`PlatformFeed`), the swipe-catching
  container, and `FeedController` (rotation, history, autoscroll, skipping, stats tracking).
- `ScrollApp/Platform.swift` – per-site URLs, ad labels and selectors. **Update these when a site changes.**
- `ScrollApp/UI/` – SwiftUI screens; statistics use Swift Charts.
- `PageScript/scrollapp.js` – the page script, identical to the Android app's
  `app/src/main/assets/scrollapp.js`. After changing it, copy it here and run `python3 PageScript/embed.py`,
  which regenerates `ScrollApp/Feed/PageScript.swift`.

Debug builds allow Safari's Web Inspector (Safari → Develop → your iPhone) to inspect the live pages;
feed events are logged under subsystem `dev.wardar.scrollapp` in Console.app.

## Limitations

- Google sometimes refuses to sign in inside an app's browser; YouTube Shorts still works logged out.
- Like/repost press the site's own buttons, so they need you to be logged in to that site.
- Skipping ads and automating these sites is against their terms of service. This is a personal app;
  it cannot go on the App Store.
