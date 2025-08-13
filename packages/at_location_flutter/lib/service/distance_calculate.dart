import 'dart:convert';
import 'package:at_location_flutter/utils/constants/constants.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

import 'api_service.dart';

class DistanceCalculate {
  DistanceCalculate._();
  static final DistanceCalculate _instance = DistanceCalculate._();
  factory DistanceCalculate() => _instance;

  /// Will calculate the ETA from [origin] to [destination].
  ///
  /// If no path is found or any other error occurs, will return '?'.
  ///
  /// Make sure that [apiKey] is passed while initialising.
  Future<String> calculateETA(LatLng origin, LatLng destination) async {
    try {
      var url =
          'https://router.hereapi.com/v8/routes?transportMode=car&origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&return=summary&apiKey=${MixedConstants.API_KEY}';
      var response = await ApiService().getRequest(url);
      var data = response;
      data = jsonDecode(data['body']);
      var _min = (data['routes'][0]['sections'][0]['summary']['duration'] / 60);
      var _time = _min > 60
          ? '${((_min / 60).toStringAsFixed(0))}hr ${(_min % 60).toStringAsFixed(0)}min'
          : '${_min.toStringAsFixed(2)}min';

      return _time;
    } catch (e) {
      // ignore: avoid_print
      print(' error in ETA');
      return '?';
    }
  }
}
