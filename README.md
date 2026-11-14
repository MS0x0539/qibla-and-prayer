# Qibla & Prayer

An iPhone app with a Qibla compass and prayer times. No ads, no subscriptions, no account, no
tracking. English, Dutch, German, French, Turkish and Arabic (right to left), switchable inside the app.
On the App Store as "Wajh: Qibla & Prayer Times".

- **Prayer times:** today's times, the next prayer with a countdown, the Hijri date, a monthly
  timetable, and a notification per prayer (standard sound). Calculated on the phone the way each
  authority computes its own tables ([Adhan](https://github.com/batoulapps/adhan-swift)'s astronomy for most;
  Diyanet, MUIS, Moonsighting and Banuri Town with their own), checked day by day against those official
  timetables (see docs/PLAN.md): 17 methods, suggested by country, language and madhab in a step-by-step
  setup; each prayer can be moved by a few minutes to match a mosque. By default ("Automatic") the method and Asr
  follow the country you're in, as its mosques calculate, also when you travel.
- **Qur'an:** the full Arabic text (Tanzil's Uthmani text, unchanged) on the 604 pages of the Madinah mushaf,
  turned right to left, in the Amiri Quran font; an index of surahs, juz and the Qur'an's du'as, and search by
  surah name (Arabic, Latin, Turkish, Dutch, German, French), du'a name or Arabic words. Bookmarks, a khatm
  (pages read, out of 604), and a tap on a verse to copy or share it. Recitation verse by verse by ten reciters,
  streamed from the app's own copy at audio.qibla.dev (an R2 bucket filled from Islamic Network's cdn.islamic.network,
  whose terms allow downloading for personal and educational use) and cached on the phone; it keeps
  playing with the screen locked, turns the pages and marks the verse being recited. Hizb, quarter and sajda
  notes in the margin as in print, a sleep timer, and offline recitation (a surah, a juz or the whole Qur'an
  downloaded into the app). A "Continue reading" card on Prayer times opens the last page read.
- **Reminders:** optionally 5-30 minutes before each prayer, an hour before Jumu'ah, and before suhoor
  ends and at iftar in Ramadan.
- **Islamic calendar:** the year's special days and nights, and a Ramadan timetable (suhoor/iftar);
  the Prayer times tab shows when Ramadan begins and, during it, suhoor and iftar with a countdown.
- **Qibla:** a compass dial with the Kaaba marker on the rim; it turns gold with a haptic tap when
  the phone faces the Qibla.
- **Map:** the Qibla as a line to the Kaaba, and mosques nearby.
- **Home and Menu:** Home opens on the next prayer as the Lock Screen shows it. Menu holds the rest as tiles: the
  tasbih (a tap counter with haptics; free counting, the tasbihat after prayer 33/33/34, or one of eight phrases shown
  in Arabic), the prayer tracker (today's fast), missed prayers and fasts, the khatm, the Islamic calendar, mosques
  nearby, Makkah live and the recitation downloads; feedback and Settings below. All kept on the phone.
- **Controls:** Qibla and Tasbih buttons for Control Center, the Lock Screen and the Action button.
- **Next prayer on the Lock Screen:** a Live Activity with a countdown (Settings → Lock Screen), moved on to the
  next prayer whenever the app runs.
- **Icon:** light, dark and tinted versions; Paper and Green alternatives in Settings.
- **Sky:** the top of the Prayer times screen takes the colour of the sky at that hour.
- **Siri:** "When is Maghrib in Qibla & Prayer?" without opening the app.
- **Iftar countdown:** on the Lock Screen and in the Dynamic Island (a Live Activity, from the Ramadan
  card or the Prayer tracker). The Next prayer widgets are built but off until the App Group is registered in
  the developer portal (see `Widgets/PrayerWidgets.swift`).
- **Location:** the phone's location, or a city picked with Apple Maps search.

## Website

`site/` builds https://qibla.dev: home, privacy policy, accessibility and support, in all six languages,
with no scripts, cookies or outside requests. `node build.mjs` writes `public/` from `content/<language>.json`
and `static/` (the favicons). The Cloudflare Worker `wajh` serves it as static assets: run
`node node_modules/wrangler/bin/cf-wrangler.js build`, then `cf deploy --prebuilt` (on Windows `cf build`
can't start Wrangler: spawn EFTYPE). Security headers come from `public/_headers`. `security.txt` expires
on 11 November 2027, so rebuild before then.

## Building

Nobody working on it has a Mac, so everything builds on GitHub (`.github/workflows/ios.yml`):

1. [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the Xcode project from `project.yml`
   (the `.xcodeproj` is not committed).
2. `xcodebuild test` builds the app and runs `Tests/` in the iPhone Simulator.
3. The app is opened in the Simulator in English, Dutch and Turkish, and a screenshot of each tab is
   saved under the run as the `screenshots` artifact.

The workflow runs on pushes to `main` and on pull requests that touch the app, and can be started by
hand from the Actions tab.

## Layout

| Path | What |
| --- | --- |
| `App/AppModel.swift` | Settings, place, notifications, background refresh |
| `App/Prayers.swift` | Place and the prayer-time calculation (also used by Siri) |
| `App/AppSettings.swift` | Calculation methods, Asr method, region-based suggestion |
| `App/LocationService.swift` | Location and compass heading |
| `App/PrayerTimesView.swift` | Prayer times tab and the monthly timetable |
| `App/QiblaView.swift` | Qibla compass |
| `App/QiblaMapView.swift` | Qibla map and mosques nearby |
| `App/TasbihView.swift` | Tasbih counter and its dhikr presets |
| `App/Quran/` | Qur'an text, reader, index, bookmarks and khatm (`QuranProgress`), recitation (`Recitation`) |
| `App/OpenScreenIntent.swift` | Opens the app on a screen; used by the controls in `Widgets/Controls.swift` |
| `App/HomeView.swift` | Home tab |
| `App/MenuView.swift` | Menu tab: the tiles, feedback, the recitation downloads |
| `App/TrackerView.swift` | Prayer tracker, missed prayers and the khatm (pages of Menu) |
| `App/PrayerIntents.swift` | Siri and Shortcuts (phrases in `App/*.lproj/AppShortcuts.strings`) |
| `Widgets/PrayerWidgets.swift` | Widget extension: next-prayer widgets and the iftar Live Activity |
| `App/IftarActivity.swift` | The Live Activity's data, shared by the app and the widgets |
| `App/SettingsView.swift` | Settings, time adjustments, first-run setup |
| `App/CitySearch.swift` | City search |
| `App/SetupView.swift` | First-run setup (language, location, method, reminders) |
| `App/IslamicCalendar.swift` | Islamic calendar and Ramadan timetable |
| `App/Localizable.xcstrings` | All text in English, Dutch, German, French, Turkish and Arabic |

Launch arguments used for screenshots: `-skipOnboarding YES`, `-startTab home|times|qibla|quran|menu`,
`-menuPage tasbih|tracker|missed|khatm|downloads|settings`,
`-showMap YES`,
`-demoHeading <degrees>` (the Simulator has no compass).
