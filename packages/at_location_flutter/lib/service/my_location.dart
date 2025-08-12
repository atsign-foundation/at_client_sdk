import 'package:geolocator/geolocator.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';
import 'package:at_utils/at_logger.dart';

/// Returns current [LatLng] of the device.
///
/// If location service is disabled or denied, returns null.
/// Else requests for permission and tries to return [LatLng] if permission granted.
Future<LatLng?> getMyLocation() async {
  final _logger = AtSignLogger('getMyLocation');

  try {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if ((permission == LocationPermission.always) ||
        (permission == LocationPermission.whileInUse)) {
      var position = await Geolocator.getCurrentPosition();
      return LatLng(position.latitude, position.longitude);
    }

    return null;
  } catch (e) {
    _logger.severe('Error in getLocation $e');
    return null;
  }
}

/// checks if location service is enabled.
Future<bool> isLocationServiceEnabled() async {
  final _logger = AtSignLogger('isLocationServiceEnabled');

  try {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    return true;
  } catch (e) {
    if (e is PermissionRequestInProgressException) {
      _logger.severe('PermissionRequestInProgressException error $e');
    } else {
      _logger.severe('$e');
    }
    return false;
  }
}

/// Returns current [LatLng] of the device without checking for permissions.
/// Use this function when it is known that location permission is enabled.
Future<LatLng?> getCurrentPosition() async {
  final _logger = AtSignLogger('getCurrentPosition');

  try {
    var position = await Geolocator.getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  } catch (e) {
    _logger.severe('$e');
    return null;
  }
}
