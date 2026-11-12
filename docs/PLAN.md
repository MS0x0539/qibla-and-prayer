# Plan

An iPhone app for the Qibla and prayer times: no ads, no subscriptions, no account, no tracking.
Apple-like and calm, in the "Geometry" look: deep green-black, gold, the eight-pointed star, serif type.

## Decided

| Topic | Decision |
| --- | --- |
| Platform | iPhone only, iOS 18 and later, portrait, dark |
| Code | Native SwiftUI; prayer times from [Adhan](https://github.com/batoulapps/adhan-swift) 1.5.0, calculated on the phone |
| Tabs | Prayer times (start screen), Qibla, Tasbih, Tracker, Settings |
| Compass | Rotating dial with the Kaaba marker on the rim; gold star and one haptic tap when facing the Qibla |
| Languages | English (default), Dutch, German, French, Turkish, Arabic (right to left), switchable inside the app |
| Calculation | The user chooses, step by step: madhab, then method (17 to choose from), suggested by country, language and madhab |
| Notifications | One per prayer (switch per prayer), optional reminder 5-30 minutes before, Jumu'ah reminder, suhoor/iftar in Ramadan; standard sound |
| Name | App Store: "Wajh: Qibla & Prayer Times" (store names must be unique); under the icon: "Qibla & Prayer" |
| Later | Duas and adhkar, Quran, zakat calculator; Apple Watch; an adhan sound |

## Built

- **Setup** (also from Settings → Run setup again): welcome, language, location (GPS or city search),
  madhab (Hanafi, Shafi'i, Maliki, Hanbali or Ja'fari, required; Hanafi also asks which Asr the mosque
  uses), method (today's Fajr and Isha shown per method to compare with the mosque), reminders, summary.
- **Prayer times:** Hijri date, next prayer with countdown, today's six times with a bell each,
  Jumu'ah on Fridays, monthly timetable, Islamic calendar with Ramadan timetable (suhoor/iftar).
  A Ramadan card: before Ramadan "begins in N days", during it suhoor and iftar with a countdown.
- **Qibla:** true-north heading, turn left/right in degrees, distance to Mecca, calibration hint, help sheet.
  A map with the Qibla line (geodesic, to the Kaaba) and mosques nearby (Apple Maps search).
- **Tasbih:** tap counter with haptics, rounds of 33 or 99 or no limit, total.
- **Tracker:** "I'm fasting today" with the iftar time, days fasted this year, fasts to make up, missed
  prayers per prayer (Witr for Hanafis). Stored only on the phone.
- **Siri and Shortcuts:** "When is the next prayer" and "When is Maghrib", answered without opening
  the app; phrases in all six languages.
- **Background refresh:** iOS wakes the app now and then to top up the notifications (at most 64 wait).
- **Iftar countdown:** a Live Activity (Lock Screen and Dynamic Island), started from the Ramadan card
  or from "I'm fasting today" in the Tracker. It needs no App Group, so it ships now.
- **Next prayer widgets (built, switched off):** next prayer, its time and a countdown (Home Screen
  small; Lock Screen rectangular and inline). They read the settings and place through the App Group
  `group.org.psbv.qiblaandprayer`, which App Store Connect API keys can't register or assign (HTTP 401,
  "Authentication failed" in the export). First register the group in the developer portal and assign it
  to `org.psbv.qiblaandprayer` and `org.psbv.qiblaandprayer.widgets`; then follow the shortcut comment in
  `Widgets/PrayerWidgets.swift`.
- **Settings:** location, madhab, method, Asr, per-prayer minute adjustments, Hijri date ±2 days,
  notifications with a test button, language, setup again, About ("Made by Melih Sivrikaya").
- **Correctness from research:** Diyanet's Asr is the standard (first-shadow) time; Diyanet outside
  Turkey uses Isha at 16°; Umm al-Qura adds 30 minutes to Isha in Ramadan; above 48° the one-seventh-
  of-the-night rule applies; times are computed in the place's own time zone.

## How it is built without a Mac

`project.yml` → XcodeGen on GitHub's `macos-26` runner (Xcode 26.6) → `xcodebuild test` in the iPhone
Simulator → a bundle check (all six languages, privacy manifest) → screenshots of every tab, every setup
page and the languages, when started by hand or with `[screenshots]` in the commit message.
The repository is private: about 190 free macOS minutes a month on GitHub Free.

## Open decisions

1. **Diyanet in the Netherlands, Belgium and Germany.** In spring and summer Diyanet's tables there use
   their own estimates; the app can be up to about 30 minutes off for Fajr and Isha. Options: copy the
   estimation rule into the app (about ±5 minutes on most days, re-check yearly), fetch Diyanet's official
   times online (needs a server or API account), or keep the note shown now.
2. **Public or private repository.** Public makes macOS builds free and unlimited.
3. **Details:** Dutch prayer names in English spelling (Fajr) or Dutch (Fadjr); France's default
   (Muslim World League or 12°); Hanafi Asr as the default in Pakistan and India.
4. **Translations** were drafted by Claude; a native speaker should check the religious terms.

## Before the first TestFlight build (owner, in App Store Connect)

All done on 12 November 2026: bundle ID registered, app record "Wajh: Qibla & Prayer Times", internal
group "me", the three `ASC_*` secrets. The first build reached App Store Connect the same night.
Upload a new build: Actions → iOS → Run workflow → "Upload to TestFlight" (or `[testflight]` in a commit
message). "Check App Store Connect key" tests the secrets on Linux without printing them.

## Before the App Store

- Privacy policy and support page (with contact details) and a link to the policy in Settings → About.
- App Privacy: "Data Not Collected". Age rating 4+. EU trader status (asked for every new app).
- Availability: leave out China mainland (religious content permit); untick Mac and Apple Vision Pro
  (no compass).
- Screenshots (iPhone 6.9" or 6.3") from the Simulator job; store name, subtitle and keywords per language.

## Later

Duas and adhkar, Quran, a zakat calculator, Apple Watch, an adhan sound (only a clip licensed for the
App Store).
