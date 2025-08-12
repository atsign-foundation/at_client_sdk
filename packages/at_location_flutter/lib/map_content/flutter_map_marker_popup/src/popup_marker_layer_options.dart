import 'package:at_location_flutter/map_content/flutter_map/src/layer/layer.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/layer/marker_layer.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_builder.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_controller.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_snap.dart';

class PopupMarkerLayerOptions extends LayerOptions {
  final List<Marker> markers;
  final PopupBuilder popupBuilder;
  final PopupController popupController;
  final PopupSnap popupSnap;

  /// Show the list of markers on the map with a popup that is shown when a
  /// marker is tapped or via the popupController.
  ///
  /// popupSnap:       To which edge of the marker the popup should snap to.
  /// popupBuilder:    A function that builds the popup for the given context
  ///                  and for the given Marker.
  /// popupController: Optional. Provide a PopupController instance to control
  ///                  popup functionality programmatically.
  PopupMarkerLayerOptions({
    this.markers = const [],
    this.popupSnap = PopupSnap.top,
    required this.popupBuilder,
    popupController,
    rebuild,
  })  : popupController = popupController ?? PopupController(),
        super(rebuild: rebuild);
}
