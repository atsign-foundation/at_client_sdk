// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

class _QuickHullDistantPoint {
  final LatLng? maxPoint;
  final List<LatLng>? newPoints;

  _QuickHullDistantPoint({this.maxPoint, this.newPoints});
}

class QuickHull {
  static double _getDistant(LatLng cpt, List<LatLng> bl) {
    var vY = bl[1].latitude - bl[0].latitude,
        vX = bl[0].longitude - bl[1].longitude;
    return (vX * (cpt.latitude - bl[0].latitude) +
        vY * (cpt.longitude - bl[0].longitude));
  }

  static _QuickHullDistantPoint _findMostDistantPointFromBaseLine(
      baseLine, latLngs) {
    // ignore: omit_local_variable_types
    double maxD = 0;
    LatLng? maxPt;
    var newPoints = <LatLng>[];

    for (var i = latLngs.length - 1; i >= 0; i--) {
      var pt = latLngs[i];
      var d = _getDistant(pt, baseLine);

      if (d > 0) {
        newPoints.add(pt);
      } else {
        continue;
      }

      if (d > maxD) {
        maxD = d;
        maxPt = pt;
      }
    }

    return _QuickHullDistantPoint(maxPoint: maxPt, newPoints: newPoints);
  }

  static List<LatLng?> _buildConvexHull(
      List<LatLng> baseLine, List<LatLng> latLngs) {
    var t = _findMostDistantPointFromBaseLine(baseLine, latLngs);

    if (t.maxPoint != null) {
      // if there is still a point "outside" the base line
      return [
        ..._buildConvexHull([baseLine[0], t.maxPoint!], t.newPoints!),
        ..._buildConvexHull([t.maxPoint!, baseLine[1]], t.newPoints!)
      ];
    } else {
      // if there is no more point "outside" the base line, the current base line is part of the convex hull
      return [baseLine[0]];
    }
  }

  static List<LatLng?> getConvexHull(List<LatLng> latLngs) {
    // find first baseline
    double? maxLat, minLat, maxLng, minLng;

    LatLng? maxLatPt, minLatPt, maxLngPt, minLngPt, maxPt, minPt;

    for (var i = latLngs.length - 1; i >= 0; i--) {
      var pt = latLngs[i];

      if (maxLat == null || pt.latitude > maxLat) {
        maxLatPt = pt;
        maxLat = pt.latitude;
      }
      if (minLat == null || pt.latitude < minLat) {
        minLatPt = pt;
        minLat = pt.latitude;
      }
      if (maxLng == null || pt.longitude > maxLng) {
        maxLngPt = pt;
        maxLng = pt.longitude;
      }
      if (minLng == null || pt.longitude < minLng) {
        minLngPt = pt;
        minLng = pt.longitude;
      }
    }

    if (minLat != maxLat) {
      minPt = minLatPt;
      maxPt = maxLatPt;
    } else {
      minPt = minLngPt;
      maxPt = maxLngPt;
    }

    return <LatLng?>[
      ..._buildConvexHull([minPt!, maxPt!], latLngs),
      ..._buildConvexHull([maxPt, minPt], latLngs)
    ];
  }
}
