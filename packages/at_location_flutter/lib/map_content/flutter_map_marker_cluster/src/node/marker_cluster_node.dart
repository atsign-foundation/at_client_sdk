// ignore_for_file: avoid_function_literals_in_foreach_calls

import 'package:at_location_flutter/map_content/flutter_map/flutter_map.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/map/map.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_cluster/src/node/marker_node.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

class MarkerClusterNode {
  final int zoom;
  final MapState? map;
  final List<dynamic> children;
  LatLngBounds bounds;
  MarkerClusterNode? parent;
  int? addCount;
  int? removeCount;

  List<MarkerNode> get markers {
    var markers = <MarkerNode>[];

    markers.addAll(children.whereType<MarkerNode>());

    children.forEach((child) {
      if (child is MarkerClusterNode) {
        markers.addAll(child.markers);
      }
    });
    return markers;
  }

  MarkerClusterNode({
    required this.zoom,
    required this.map,
  })  : bounds = LatLngBounds(),
        children = [],
        parent = null;

  LatLng? get point {
    var swPoint = map!.project(bounds.southWest);
    var nePoint = map!.project(bounds.northEast);
    return map!.unproject((swPoint + nePoint) / 2);
  }

  void addChild(dynamic child) {
    assert(child is MarkerNode || child is MarkerClusterNode);
    children.add(child);
    child.parent = this;
    bounds.extend(child.point);
  }

  void removeChild(dynamic child) {
    children.remove(child);
    recalculateBounds();
  }

  void recalculateBounds() {
    bounds = LatLngBounds();

    markers.forEach((marker) {
      bounds.extend(marker.point);
    });

    children.forEach((child) {
      if (child is MarkerClusterNode) {
        child.recalculateBounds();
      }
    });
  }

  void recursively(
      int? zoomLevel, int disableClusteringAtZoom, Function(dynamic) fn) {
    if (zoom == zoomLevel && zoomLevel! <= disableClusteringAtZoom) {
      fn(this);
      return;
    }

    children.forEach((child) {
      if (child is MarkerNode) {
        fn(child);
      }
      if (child is MarkerClusterNode) {
        child.recursively(zoomLevel, disableClusteringAtZoom, fn);
      }
    });
  }
}
