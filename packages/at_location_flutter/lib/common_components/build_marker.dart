import 'package:at_location_flutter/map_content/flutter_map/src/layer/marker_layer.dart';
import 'package:at_location_flutter/location_modal/hybrid_model.dart';
import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:flutter/material.dart';

import 'circle_marker_painter.dart';
import 'contacts_initial.dart';
import 'custom_circle_avatar.dart';
import 'marker_custom_painter.dart';

/// Builds a marker for the given [user]
Marker buildMarker(HybridModel user,
    {bool singleMarker = false, Widget? marker}) {
  return Marker(
    anchorPos: AnchorPos.align(AnchorAlign.center),
    height: 75,
    width: 50,
    point: user.latLng!,
    // ignore: prefer_if_null_operators
    builder: (ctx) => marker != null
        ? marker
        : (singleMarker
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    bottom: 25,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CustomPaint(
                        painter: CircleMarkerPainter(
                            color: AllColors().WHITE,
                            paintingStyle: PaintingStyle.fill),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    child: Icon(
                      Icons.circle,
                      size: 40,
                      color: AllColors().DARK_BLUE,
                    ),
                  ),
                ],
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    bottom: 25,
                    child: CustomPaint(
                      size: Size(40, (40 * 1.137455469677715).toDouble()),
                      painter: RPSCustomPainter(),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: AllColors().ORANGE,
                      child: user.image != null
                          ? CustomCircleAvatar(
                              byteImage: user.image, nonAsset: true, size: 30)
                          : ContactInitial(
                              initials: user.displayName,
                              size: 30,
                              backgroundColor: AllColors().ORANGE,
                            ),
                    ),
                  ),
                ],
              )),
  );
}
