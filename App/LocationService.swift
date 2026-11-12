import CoreLocation
import Foundation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// Degrees clockwise from true north (magnetic north when true north is unknown); nil without a compass.
    private(set) var heading: Double?
    /// The same heading without the jump from 359° to 0°, so the dial turns the short way round.
    private(set) var continuousHeading: Double = 0
    /// Error margin in degrees; negative means the compass needs calibrating.
    private(set) var headingAccuracy: Double = -1
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored var onPlace: ((Place) -> Void)?
    @ObservationIgnored private var lastResolved: CLLocation?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.headingFilter = 1
        authorization = manager.authorizationStatus
        // For CI screenshots: the Simulator has no compass, so `-demoHeading 100` fakes one.
        if let demo = UserDefaults.standard.string(forKey: "demoHeading").flatMap(Double.init) {
            heading = demo
            continuousHeading = demo
            headingAccuracy = 5
        }
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            refresh()
        }
    }

    func refresh() {
        if isAuthorized { manager.requestLocation() }
    }

    func startHeading() {
        // True north (trueHeading) is only valid while the same manager also delivers locations;
        // without it the heading falls back to magnetic north, 3-6° off in the Netherlands and Turkey.
        if isAuthorized { manager.startUpdatingLocation() }
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stopHeading() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Within a kilometre of the last named place nothing changes, so skip the lookup.
        if let last = lastResolved, last.distance(from: location) < 1_000 { return }
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            let mark = marks?.first
            if mark != nil { self?.lastResolved = location }
            self?.onPlace?(Place(
                name: mark?.locality ?? mark?.name ?? "",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timeZoneID: (mark?.timeZone ?? .current).identifier,
                countryCode: mark?.isoCountryCode))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if let previous = heading {
            var delta = (value - previous).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
            continuousHeading += delta
        } else {
            continuousHeading = value
        }
        heading = value
        headingAccuracy = newHeading.headingAccuracy
    }

    /// The Qibla screen shows its own, non-blocking calibration hint instead of iOS's full-screen one.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }
}
