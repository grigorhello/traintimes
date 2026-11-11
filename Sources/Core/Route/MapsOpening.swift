import MapKit
import UIKit

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
        if #available(iOS 26, *) {
            let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
            item.name = name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        } else if let url = URL(string: "maps://?daddr=\(place.latitude),\(place.longitude)") {
            // Before iOS 26 an MKMapItem takes a coordinate only through MKPlacemark, which the SDK deprecates (warnings
            // are errors): Maps' own link, with no travel type so Maps uses the rider's. The destination has no name here.
            UIApplication.shared.open(url)
        }
    }
}
