// ignore_for_file: prefer_void_to_null, prefer_const_constructors_in_immutables, use_key_in_widget_constructors, avoid_unnecessary_containers

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/core/bounds.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/core/point.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/layer/marker_layer.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/map/map.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/marker_popup.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_marker_layer_options.dart';

class PopupMarkerLayer extends StatelessWidget {
  /// For normal layer behaviour
  final PopupMarkerLayerOptions layerOpts;
  final MapState? map;
  final Stream<Null> stream;

  PopupMarkerLayer(this.layerOpts, this.map, this.stream);

  bool _boundsContainsMarker(Marker marker) {
    var pixelPoint = map!.project(marker.point);

    final width = marker.width - marker.anchor.left;
    final height = marker.height - marker.anchor.top;

    var sw = CustomPoint(pixelPoint.x + width, pixelPoint.y - height);
    var ne = CustomPoint(pixelPoint.x - width, pixelPoint.y + height);
    return map!.pixelBounds!.containsPartialBounds(Bounds(sw, ne));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
      stream: stream, // a Stream<int> or null
      builder: (BuildContext _, AsyncSnapshot<int?> __) {
        var markers = <Widget>[];

        for (var markerOpt in layerOpts.markers) {
          var pos = map!.project(markerOpt.point);
          pos = pos.multiplyBy(map!.getZoomScale(map!.zoom, map!.zoom)) -
              map!.getPixelOrigin()!;

          var pixelPosX =
              (pos.x - (markerOpt.width - markerOpt.anchor.left)).toDouble();
          var pixelPosY =
              (pos.y - (markerOpt.height - markerOpt.anchor.top)).toDouble();

          if (!_boundsContainsMarker(markerOpt)) {
            continue;
          }

          var bottomPos = map!.pixelBounds!.max;
          bottomPos =
              bottomPos.multiplyBy(map!.getZoomScale(map!.zoom, map!.zoom)) -
                  map!.getPixelOrigin()!;

          markers.add(
            Positioned(
              width: markerOpt.width,
              height: markerOpt.height,
              left: pixelPosX,
              top: pixelPosY,
              child: GestureDetector(
                onTap: () => layerOpts.popupController.togglePopup(markerOpt),
                child: markerOpt.builder(context),
              ),
            ),
          );
        }

        markers.add(
          MarkerPopup(
            mapState: map,
            popupController: layerOpts.popupController,
            snap: layerOpts.popupSnap,
            popupBuilder: layerOpts.popupBuilder,
          ),
        );

        return Container(
          child: Stack(
            children: markers,
          ),
        );
      },
    );
  }
}
