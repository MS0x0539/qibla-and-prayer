# Plan

An iPhone app for the Qibla and prayer times: no ads, no subscriptions, no account, no tracking.
Apple-like and calm, in the "Geometry" look: deep green-black, gold, the eight-pointed star, serif type.

## Decided

| Topic | Decision |
| --- | --- |
| Platform | iPhone only, iOS 18 and later, portrait, dark |
| Code | Native SwiftUI; prayer times from [Adhan](https://github.com/batoulapps/adhan-swift) 1.5.0, calculated on the phone |
| Tabs | Prayer times (start screen), Qibla, Qur'an, Ibadah (tasbih and tracker), Settings |
| Compass | Rotating dial with the Kaaba marker on the rim; gold star and one haptic tap when facing the Qibla |
| Languages | English (default), Dutch, German, French, Turkish, Arabic (right to left), switchable inside the app |
| Calculation | "Automatic" by default: the method and Asr of the country the times are for (and the language), also when travelling; any of the 17 methods, the Asr and the madhab can be fixed in Settings. The setup no longer asks the madhab (13 November 2026). |
| Qur'an | Arabic only: Tanzil's Uthmani text (CC BY 3.0, unchanged, credited with a link) on the Madinah mushaf's 604 pages, Amiri Quran font (OFL). The exact Madinah calligraphy and 15-line layout (King Fahd Complex page fonts) needs the Complex's written permission first. |
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
  notifications with a test button, language, setup again, About ("Made by Melih Sivrikaya", privacy
  policy, support, acknowledgements with Adhan's MIT licence).
- **Correctness:** each method computes the way its authority computes its own published tables; see
  "How the times were checked". Times are computed in the place's own time zone.

## How the times were checked

Each method was compared day by day with its authority's own published tables, at the authority's
reference point, and the calculation (`App/PrayerEngine.swift`, `App/DiyanetTimes.swift`) was rebuilt until
it matched. Share of times identical to the minute, November 2026:

| Method | Official tables | Before | Now |
| --- | --- | --- | --- |
| Diyanet | namazvakitleri.diyanet.gov.tr 2026: 7 cities here, 151 places in the reconstruction | 43.3% | 99.96% |
| Moonsighting Committee | moonsighting.com, London, Amsterdam, New York, 2026-2027 | 74.6% | 99.9% |
| Umm al-Qura | KACST (ummulqura.org.sa), Makkah, Madinah, Riyadh, Jeddah, Dammam, 394 days | 50.4% | 96.7% |
| Qatar | Qatar Calendar House, Doha, 474 days | 17.6% | 97.4% |
| Dubai | Awqaf (UAE), Dubai, 2025-2027 | 59.9% | 98.7% |
| Singapore | MUIS (data.gov.sg), 2026 | 71.2% | 99.7% |
| Malaysia | JAKIM (e-solat), WLY01, 2026 | 92.0% | 95.8% |
| Indonesia | Kemenag (SIHAT), 3 cities, 2026 | 94.1% | 98.6% |
| Egypt | ESA, Cairo, Alexandria, Aswan, 2026 | 75.4% | 97.1% |
| Karachi | Banuri Town, 2026 | 77.9% | 100% |
| Kuwait | the Al-Ojeiri table | 72.3% | 75.5% |
| Tehran | Institute of Geophysics, 1402-1404 SH | 99.1% | 99.1% |
| Morocco | Habous, 7 cities, 883 days | 52.8% | 59.4% |

Nearly every remaining difference is one minute, where the authority's figure lies within a second or so of a
minute boundary. Known limits:
- KACST prints the previous day's times on a few dates a month (5% of days), a quirk of its service.
- MUIS shifts its table by a day in some years (2025 the other way); see the shortcut in AppSettings.swift.
- Morocco needs each town's horizon height (Habous publishes 190 towns) to get closer; not done yet.
- Kuwait's official table is a fixed one from about 1978; not reproduced.
- An authority's table is for its reference point; at the user's own position a time can differ by a minute.
- Authorities change their rules now and then (Qatar in 1447, Diyanet's Yatsı temkin since 2020): re-check
  each year against the new tables. The comparison scripts and data are not in this repository.

## How it is built without a Mac

`project.yml` → XcodeGen on GitHub's `macos-26` runner (Xcode 26.6) → `xcodebuild test` in the iPhone
Simulator → a bundle check (all six languages, privacy manifest) → screenshots of every tab, every setup
page and the languages, when started by hand or with `[screenshots]` in the commit message.
The repository is private: about 190 free macOS minutes a month on GitHub Free.

## Open decisions

1. **Diyanet in the Netherlands, Belgium and Germany:** done 13 November 2026. The app now reproduces
   Diyanet's own summer estimates (takdir) there, so the note about half an hour is gone.
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

- Done 12 November 2026: privacy policy, accessibility and support pages on https://qibla.dev in all six
  languages, linked from Settings → About (privacy and support).
- App Privacy: "Data Not Collected". Age rating 4+. EU trader status (asked for every new app).
- Availability: leave out China mainland (religious content permit); untick Mac and Apple Vision Pro
  (no compass).
- Screenshots (iPhone 6.9" or 6.3") from the Simulator job; store name, subtitle and keywords per language.

## Later

Duas and adhkar, Quran, a zakat calculator, Apple Watch, an adhan sound (only a clip licensed for the
App Store).
