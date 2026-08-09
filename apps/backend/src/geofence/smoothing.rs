use super::models::{LocationFix, Point};

pub fn median_smoothed_fix(current: LocationFix, recent: &[Option<LocationFix>; 3]) -> LocationFix {
    let mut latitudes = vec![current.point.latitude];
    let mut longitudes = vec![current.point.longitude];

    for fix in recent.iter().flatten() {
        latitudes.push(fix.point.latitude);
        longitudes.push(fix.point.longitude);
    }

    LocationFix {
        point: Point {
            latitude: median(&mut latitudes),
            longitude: median(&mut longitudes),
        },
        accuracy_meters: current.accuracy_meters,
        captured_at: current.captured_at,
    }
}

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    values[values.len() / 2]
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn smooths_single_spike() {
        let now = Utc::now();
        let current = LocationFix {
            point: Point {
                latitude: 13.2,
                longitude: 77.8,
            },
            accuracy_meters: Some(10.0),
            captured_at: now,
        };
        let recent = [
            Some(LocationFix {
                point: Point {
                    latitude: 12.9716,
                    longitude: 77.5946,
                },
                accuracy_meters: Some(10.0),
                captured_at: now,
            }),
            Some(LocationFix {
                point: Point {
                    latitude: 12.9717,
                    longitude: 77.5947,
                },
                accuracy_meters: Some(10.0),
                captured_at: now,
            }),
            None,
        ];

        let smoothed = median_smoothed_fix(current, &recent);

        assert!(smoothed.point.latitude < 13.0);
    }
}
