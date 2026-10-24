import 'dart:math';

import '../models/location_share.dart';

/// Produces the device's current [LocationPoint], or `null` if one isn't
/// available right now.
typedef LocationProvider = Future<LocationPoint?> Function();

/// A dependency-free stand-in for a real device GPS. Starts at [origin] and
/// takes a small random walk on each call, so a demo run shows visible
/// movement without needing a location plugin or platform permissions.
///
/// Swap this for a real GPS-backed [LocationProvider] (e.g. one built on the
/// `geolocator` package) in an app that needs actual positions; the rest of
/// this example — [LocationSharingService], the screens — doesn't care which
/// provider it's given.
class SimulatedLocationProvider {
  SimulatedLocationProvider({
    LocationPoint? origin,
    double stepDegrees = 0.0015,
    Random? random,
  }) : _stepDegrees = stepDegrees,
       _random = random ?? Random(),
       _current =
           origin ?? LocationPoint(latitude: 37.7749, longitude: -122.4194);

  final double _stepDegrees;
  final Random _random;
  LocationPoint _current;

  Future<LocationPoint?> call() async {
    _current = LocationPoint(
      latitude: _current.latitude + _jitter(),
      longitude: _current.longitude + _jitter(),
      accuracyMeters: 5,
    );
    return _current;
  }

  double _jitter() => (_random.nextDouble() * 2 - 1) * _stepDegrees;
}
