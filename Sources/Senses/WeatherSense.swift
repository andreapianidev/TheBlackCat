import CoreLocation
import Foundation

/// The weather outside, from an approximate position and Open-Meteo (no API key).
final class WeatherSense: NSObject, CLLocationManagerDelegate {
    var onWeather: ((WeatherMood, String) -> Void)?
    private(set) var summary = ""

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: break
        default: manager.requestLocation()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.manager.requestLocation()
        }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard running else { return }
        switch manager.authorizationStatus {
        case .notDetermined, .denied, .restricted: break
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running, let loc = locations.last else { return }
        Task { await fetch(loc.coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private struct Response: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var precipitation: Double
            var weather_code: Int
            var is_day: Int
            var cloud_cover: Double
        }
        var current: Current
    }

    private func fetch(_ c: CLLocationCoordinate2D) async {
        let lat = String(format: "%.2f", c.latitude), lon = String(format: "%.2f", c.longitude)
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,precipitation,weather_code,is_day,cloud_cover"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return }
        let w = r.current
        let rainy = w.precipitation > 0.1 || (51...67).contains(w.weather_code) || (80...82).contains(w.weather_code) || w.weather_code >= 95
        let mood: WeatherMood
        if rainy { mood = .rain }
        else if w.temperature_2m >= 29 { mood = .heat }
        else if w.temperature_2m <= 8 { mood = .cold }
        else if w.is_day == 1 && w.cloud_cover < 35 && w.weather_code <= 2 { mood = .sun }
        else { mood = .mild }
        let text = "\(Int(w.temperature_2m.rounded())) gradi, " + (rainy ? "piove" : (mood == .sun ? "sole" : "nuvoloso o sereno"))
        await MainActor.run {
            self.summary = text
            self.onWeather?(mood, text)
        }
    }
}
