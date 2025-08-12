// ignore_for_file: prefer_typing_uninitialized_variables

import 'dart:async';
import 'dart:convert';
import 'package:at_location_flutter/location_modal/location_modal.dart';
import 'package:at_location_flutter/utils/constants/constants.dart';
import 'package:http/http.dart' as http;
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

class SearchLocationService {
  SearchLocationService._();
  // ignore: prefer_final_fields
  static SearchLocationService _instance = SearchLocationService._();
  factory SearchLocationService() => _instance;

  final String placesUrl =
      'https://places.ls.hereapi.com/places/v1/autosuggest';

  // ignore: close_sinks
  final _atLocationStreamController =
      StreamController<List<LocationModal>>.broadcast();
  Stream<List<LocationModal>> get atLocationStream =>
      _atLocationStreamController.stream;
  StreamSink<List<LocationModal>> get atLocationSink =>
      _atLocationStreamController.sink;

  /// Adds location matching to [address] to [atLocationSink].
  /// If [currentLocation] is passed then will add locations nearby the [currentLocation].
  ///
  /// Make sure that [apiKey] is passed while initialising.
  void getAddressLatLng(String address, LatLng? currentLocation) async {
    currentLocation ??= const LatLng(0, 0);

    var url =
        '$placesUrl?q=${address.replaceAll(RegExp(' '), '+')}&apiKey=${MixedConstants.API_KEY}&at=${currentLocation.latitude},${currentLocation.longitude}';

    var response = await http.get(Uri.parse(url));
    var addresses = jsonDecode(response.body);
    List data = addresses['results'];
    var share = <LocationModal>[];
    //// Removed because of nulls safety
    // for (Map ad in data ?? []) {
    for (Map ad in data) {
      if (ad['resultType'] == 'place') {
        share.add(LocationModal.fromJson(ad));
      }
    }

    atLocationSink.add(share);
  }
}
