# Qibla & Prayer

An iPhone app with a Qibla compass and prayer times. No ads, no subscriptions, no account, no
tracking. English, Dutch, German, French, Turkish and Arabic (right to left), switchable inside the app.
(Working name: the App Store name is still to be chosen.)

- **Prayer times:** today's times, the next prayer with a countdown, the Hijri date, a monthly
  timetable, and a notification per prayer (standard sound). Calculated on the phone with
  [Adhan](https://github.com/batoulapps/adhan-swift): 17 methods (Adhan's 12 plus Ja'fari, Morocco,
  Malaysia, Indonesia and France), suggested by country, language and madhab in a step-by-step setup;
  each prayer can be moved by a few minutes to match a mosque.
- **Islamic calendar:** the year's special days and nights, and a Ramadan timetable (suhoor/iftar).
- **Qibla:** a compass dial with the Kaaba marker on the rim; it turns gold with a haptic tap when
  the phone faces the Qibla.
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
| `App/AppModel.swift` | Settings, place, prayer-time calculation, notifications |
| `App/AppSettings.swift` | Calculation methods, Asr method, region-based suggestion |
| `App/LocationService.swift` | Location and compass heading |
| `App/PrayerTimesView.swift` | Prayer times tab and the monthly timetable |
| `App/QiblaView.swift` | Qibla compass |
| `App/SettingsView.swift` | Settings, time adjustments, first-run setup |
| `App/CitySearch.swift` | City search |
| `App/SetupView.swift` | First-run setup (language, location, madhab, method, reminders) |
| `App/IslamicCalendar.swift` | Islamic calendar and Ramadan timetable |
| `App/Localizable.xcstrings` | All text in English, Dutch, German, French, Turkish and Arabic |

Launch arguments used for screenshots: `-skipOnboarding YES`, `-startTab times|qibla|settings`,
`-demoHeading <degrees>` (the Simulator has no compass).
