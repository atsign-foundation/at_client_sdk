import 'dart:async';

import 'package:at_location_flutter/map_content/flutter_map/src/layer/marker_layer.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_event.dart';

class PopupController {
  StreamController<PopupEvent>? streamController;

  /// Hide the popup if it is showing.
  void hidePopup() {
    streamController?.add(PopupEvent.hideAny());
  }

  /// Hide the popup but only if it is showing for one of the given markers.
  void hidePopupIfShowingFor(List<Marker?> markers) {
    streamController?.add(PopupEvent.hideInList(markers));
  }

  /// Hide the popup if it is showing for the given marker, otherwise show it
  /// for that marker.
  void togglePopup(Marker? marker) {
    streamController?.add(PopupEvent.toggle(marker));
  }

  /// Show the popup for the given marker. If the popup is already showing for
  /// that marker nothing happens.
  void showPopupFor(Marker marker) {
    streamController?.add(PopupEvent.show(marker));
  }
}
