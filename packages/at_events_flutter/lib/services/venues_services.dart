import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_utils/at_logger.dart';
import 'package:latlong2/latlong.dart';

import 'dart:collection';

class VenuesServices {
  VenuesServices._();

  static final _instance = VenuesServices._();

  factory VenuesServices() => _instance;

  final _logger = AtSignLogger('VenuesServices');

  Queue<VenueLatLng> venues = Queue<VenueLatLng>(); // LatLng() : 'venue';
  int maxLengthOfVenues = 10;
  var venueLatLngKey = 'reusablevenues';

  /// retrieves the list of venues from the storage location specified by [venueLatLngKey]
  getVenues() async {
    venues = Queue<VenueLatLng>(); // reset

    try {
      var atKey = AtKey()
        ..metadata = Metadata()
        ..metadata.ttr = -1
        ..metadata.ccd = true
        ..key = venueLatLngKey;
      var value = await AtClientManager.getInstance()
          .atClient
          .get(atKey)
          .catchError((e) async {
        await _storeVenue(Queue<VenueLatLng>());
        return AtValue();
      });

      // ignore: unnecessary_null_comparison
      if (value != null && value.value != null) {
        var _res = jsonDecode(value.value);
        Queue<VenueLatLng> _tempVenues = Queue<VenueLatLng>();
        _res['venues'].forEach((e) {
          _tempVenues.add(VenueLatLng.fromJson(e));
        });
        venues = _tempVenues;
      }
    } catch (e) {
      _logger.severe('Error in getVenues $e');
    }
  }

  /// stores a new venue in the local storage
  storeNewVenue(LatLng _latLng, String _venue, {String? displayName}) async {
    if (alreadyExists(VenueLatLng(
      _venue,
      latitude: _latLng.latitude,
      longitude: _latLng.longitude,
      displayName: displayName,
    ))) {
      return;
    }

    Queue<VenueLatLng> _tempVenues = venues;

    if (venues.length == 10) {
      _tempVenues.removeFirst();
    }

    _tempVenues.add(VenueLatLng(_venue,
        latitude: _latLng.latitude,
        longitude: _latLng.longitude,
        displayName: displayName));
    await _storeVenue(_tempVenues);
  }

  /// persists the updated [venues] queue to the storage
  Future<void> _storeVenue(Queue<VenueLatLng> _tempVenues) async {
    try {
      var atKey = AtKey()
        ..metadata = Metadata()
        ..metadata.ttr = -1
        ..metadata.ccd = true
        ..key = venueLatLngKey;

      var _convertedObject = _tempVenues
          .toList()
          .map(
            (e) => e.toJson(),
          )
          .toList();

      var _value = json.encode({
        'venues': _convertedObject,
      });

      var result = await AtClientManager.getInstance().atClient.put(
            atKey,
            _value,
          );

      if (result == true) {
        venues = _tempVenues;
      }
    } catch (e) {
      _logger.severe('Error in _storeVenue $e');
    }
  }

  /// checks if a given [_newVenue] already exists in the [venues] queue
  bool alreadyExists(VenueLatLng _newVenue) {
    for (var _venue in venues) {
      if (_venue.compare(_newVenue)) {
        return true;
      }
    }

    return false;
  }

  /// clears the [venues] queue
  clear() {
    venues = Queue<VenueLatLng>();
  }
}

class VenueLatLng {
  late double latitude, longitude;
  late String venue;
  String? displayName;

  VenueLatLng(
    this.venue, {
    required this.latitude,
    required this.longitude,
    this.displayName,
  });

  VenueLatLng.fromJson(Map<String, dynamic> data) {
    venue = data['venue'] ?? '';
    displayName = data['displayName'];
    latitude = data['latitude'] != 'null' && data['latitude'] != null
        ? double.parse(data['latitude'])
        : 0;
    longitude = data['longitude'] != 'null' && data['longitude'] != null
        ? double.parse(data['longitude'])
        : 0;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['latitude'] = latitude.toString();
    data['longitude'] = longitude.toString();
    data['venue'] = venue.toString();
    data['displayName'] = displayName?.toString();
    return data;
  }

  /// compares two VenueLatLng objects for equality
  bool compare(VenueLatLng _venueLatLng) {
    if ((latitude == _venueLatLng.latitude) &&
        (longitude == _venueLatLng.longitude) &&
        (venue == _venueLatLng.venue) &&
        (displayName == _venueLatLng.displayName)) {
      return true;
    }

    return false;
  }
}
