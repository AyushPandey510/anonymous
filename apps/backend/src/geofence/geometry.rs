use super::models::Point;

const EARTH_RADIUS_M: f64 = 6_371_000.0;

pub fn distance_meters(a: Point, b: Point) -> f64 {
    let d_lat = (b.latitude - a.latitude).to_radians();
    let d_lon = (b.longitude - a.longitude).to_radians();
    let lat1 = a.latitude.to_radians();
    let lat2 = b.latitude.to_radians();
    let h = (d_lat / 2.0).sin().powi(2) + lat1.cos() * lat2.cos() * (d_lon / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * h.sqrt().asin()
}

pub fn contains(center: Point, radius_meters: i32, candidate: Point) -> bool {
    distance_meters(center, candidate) <= radius_meters as f64
}

pub fn valid_lat_lon(latitude: f64, longitude: f64) -> bool {
    latitude.is_finite()
        && longitude.is_finite()
        && (-90.0..=90.0).contains(&latitude)
        && (-180.0..=180.0).contains(&longitude)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contains_nearby_point() {
        let center = Point {
            latitude: 12.9716,
            longitude: 77.5946,
        };
        let nearby = Point {
            latitude: 12.9720,
            longitude: 77.5946,
        };
        assert!(contains(center, 100, nearby));
    }

    #[test]
    fn rejects_far_point() {
        let center = Point {
            latitude: 12.9716,
            longitude: 77.5946,
        };
        let far = Point {
            latitude: 12.9816,
            longitude: 77.5946,
        };
        assert!(!contains(center, 100, far));
    }
}
