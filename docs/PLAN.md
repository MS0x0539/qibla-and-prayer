# Plan

An iPhone app for the Qibla and prayer times: no ads, no subscriptions, no account, no tracking.
Apple-like and calm, in the "Geometry" look: deep green-black, gold, the eight-pointed star, serif type.

## Decided

| Topic | Decision |
| --- | --- |
| Platform | iPhone only, iOS 18 and later, portrait, dark |
| Code | Native SwiftUI; prayer times from [Adhan](https://github.com/batoulapps/adhan-swift) 1.5.0, calculated on the phone |
| Tabs | Prayer times (start screen), Qibla, Settings |
| Compass | Rotating dial with the Kaaba marker on the rim; gold star and one haptic tap when facing the Qibla |
| Languages | English (default), Dutch, German, French, Turkish, Arabic (right to left), switchable inside the app |
| Calculation | The user chooses, step by step: madhab, then method (17 to choose from), suggested by country, language and madhab |
| Notifications | One per prayer, standard sound, can be switched per prayer |
| Later | Home-screen widgets, adhan sound |

## Built (version 1, not compiled yet)

- **Setup** (also from Settings → Run setup again): welcome, language, location (GPS or city search),
  madhab (Hanafi, Shafi'i, Maliki, Hanbali, Ja'fari, not sure; Hanafi also asks which Asr the mosque
  uses), method (today's Fajr and Isha shown per method to compare with the mosque), reminders, summary.
- **Prayer times:** Hijri date, next prayer with countdown, today's six times with a bell each,
  Jumu'ah on Fridays, monthly timetable, Islamic calendar with Ramadan timetable (suhoor/iftar).
- **Qibla:** true-north heading, turn left/right in degrees, distance to Mecca, calibration hint, help sheet.
- **Settings:** location, madhab, method, Asr, per-prayer minute adjustments, Hijri date ±2 days,
  notifications with a test button, language, setup again, About ("Made by" still empty).
- **Correctness from research:** Diyanet's Asr is the standard (first-shadow) time; Diyanet outside
  Turkey uses Isha at 16°; Umm al-Qura adds 30 minutes to Isha in Ramadan; above 48° the one-seventh-
  of-the-night rule applies; times are computed in the place's own time zone.

## How it is built without a Mac

`project.yml` → XcodeGen on GitHub's `macos-26` runner (Xcode 26.6) → `xcodebuild test` in the iPhone
Simulator → a bundle check (all six languages, privacy manifest) → screenshots of every tab, every setup
page and the languages, when started by hand or with `[screenshots]` in the commit message.
The repository is private: about 190 free macOS minutes a month on GitHub Free.

## Open decisions

1. **Name.** Shortlist: Wajh, Tawajjuh. (The bundle ID is settled: `org.psbv.qiblaandprayer`,
   registered as an explicit App ID.)
2. **Diyanet in the Netherlands, Belgium and Germany.** In spring and summer Diyanet's tables there use
   their own estimates; the app can be up to about 30 minutes off for Fajr and Isha. Options: copy the
   estimation rule into the app (about ±5 minutes on most days, re-check yearly), fetch Diyanet's official
   times online (needs a server or API account), or keep the note shown now.
3. **Public or private repository.** Public makes macOS builds free and unlimited.
4. **Details:** Dutch prayer names in English spelling (Fajr) or Dutch (Fadjr); France's default
   (Muslim World League or 12°); Hanafi Asr as the default in Pakistan and India.
5. **Translations** were drafted by Claude; a native speaker should check the religious terms.

## Before the first TestFlight build (owner, in App Store Connect)

1. ~~Register the bundle ID~~ Done: `org.psbv.qiblaandprayer`.
2. Create the app record (the name must be free in every language it is listed in).
3. Create an internal TestFlight group with automatic distribution.
4. Add the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the Admin key from Esports Atlas works).

Then the TestFlight job (the same unsigned-archive and cloud-signing route as Esports Atlas) is added.
Version 1 uses no entitlements, so that route works unchanged.

## Before the App Store

- Privacy policy and support page (with contact details) and a link to the policy in Settings → About.
- App Privacy: "Data Not Collected". Age rating 4+. EU trader status (asked for every new app).
- Availability: leave out China mainland (religious content permit); untick Mac and Apple Vision Pro
  (no compass).
- Screenshots (iPhone 6.9" or 6.3") from the Simulator job; store name, subtitle and keywords per language.

## Later

Reminders a few minutes before a prayer, Qibla on a map, nearby mosques, widgets and a Live Activity
countdown, Apple Watch, an adhan sound (only a clip licensed for the App Store), background refresh so
notifications continue when the app isn't opened for two weeks.
