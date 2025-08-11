import 'dart:typed_data';
import 'package:at_location_flutter/map_content/flutter_map/flutter_map.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

/// Model containing the [displayName], [image], [eta], [marker] associated with the [latLng].
class HybridModel {
  String? displayName;
  Uint8List? image;
  LatLng? latLng;
  String? eta = '?';
  Marker? marker;
  HybridModel({
    this.displayName,
    this.eta,
    this.image,
    this.latLng,
    this.marker,
  });
}
