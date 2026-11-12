# Qibla & Prayer

An iPhone app with a Qibla compass and prayer times. No ads, no subscriptions, no account, no
tracking. English, Dutch, German, French, Turkish and Arabic (right to left), switchable inside the app.
On the App Store as "Wajh: Qibla & Prayer Times".

- **Prayer times:** today's times, the next prayer with a countdown, the Hijri date, a monthly
  timetable, and a notification per prayer (standard sound). Calculated on the phone with
  [Adhan](https://github.com/batoulapps/adhan-swift): 17 methods (Adhan's 12 plus Ja'fari, Morocco,
  Malaysia, Indonesia and France), suggested by country, language and madhab in a step-by-step setup;
  each prayer can be moved by a few minutes to match a mosque.
- **Reminders:** optionally 5-30 minutes before each prayer, an hour before Jumu'ah, and before suhoor
  ends and at iftar in Ramadan.
- **Islamic calendar:** the year's special days and nights, and a Ramadan timetable (suhoor/iftar);
  the Prayer times tab shows when Ramadan begins and, during it, suhoor and iftar with a countdown.
- **Qibla:** a compass dial with the Kaaba marker on the rim; it turns gold with a haptic tap when
  the phone faces the Qibla.
- **Map:** the Qibla as a line to the Kaaba, and mosques nearby.
- **Tasbih:** a tap counter with haptics. **Tracker:** fasts and missed prayers, kept on the phone.
- **Siri:** "When is Maghrib in Qibla & Prayer?" without opening the app.
- **Iftar countdown:** on the Lock Screen and in the Dynamic Island (a Live Activity, from the Ramadan
  card or the Tracker). The Next prayer widgets are built but off until the App Group is registered in
  the developer portal (see `Widgets/PrayerWidgets.swift`).
- **Location:** the phone's location, or a city picked with Apple Maps search.

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
| `App/TasbihView.swift` | Tasbih counter |
| `App/TrackerView.swift` | Fasting and missed-prayer tracker |
| `App/PrayerIntents.swift` | Siri and Shortcuts (phrases in `App/*.lproj/AppShortcuts.strings`) |
| `Widgets/PrayerWidgets.swift` | Widget extension: next-prayer widgets and the iftar Live Activity |
| `App/IftarActivity.swift` | The Live Activity's data, shared by the app and the widgets |
| `App/SettingsView.swift` | Settings, time adjustments, first-run setup |
| `App/CitySearch.swift` | City search |
| `App/SetupView.swift` | First-run setup (language, location, madhab, method, reminders) |
| `App/IslamicCalendar.swift` | Islamic calendar and Ramadan timetable |
| `App/Localizable.xcstrings` | All text in English, Dutch, German, French, Turkish and Arabic |

Launch arguments used for screenshots: `-skipOnboarding YES`, `-startTab times|qibla|tasbih|tracker|settings`,
`-showMap YES`,
`-demoHeading <degrees>` (the Simulator has no compass).
