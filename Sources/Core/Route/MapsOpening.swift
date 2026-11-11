import MapKit

/// Hands a trip off to Apple Maps (TT-188, D64): directions to a station, behind a protocol so tests check the tap
/// without leaving the app.
@MainActor
protocol MapsOpening {
    /// Apple Maps with directions to the place, named `name`, in the travel type the rider set in Maps. No location
    /// permission: Maps starts from where the rider is.
    func openDirections(to name: String, at place: GeoPoint)
}

@MainActor
struct SystemMapsOpener: MapsOpening {
    func openDirections(to name: String, at place: GeoPoint) {
        let item: MKMapItem
        if #available(iOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        } else {
            // Deprecated from iOS 26 only, above the iOS 17 deployment target, so it builds without a warning.
            let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
