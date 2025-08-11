import 'package:at_location_flutter/map_content/flutter_map/src/layer/marker_layer.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_event_actions.dart';

class PopupEvent {
  final Marker? marker;
  final List<Marker?>? markers;
  final PopupEventActions action;

  PopupEvent.hideInList(this.markers)
      : marker = null,
        action = PopupEventActions.hideInList;

  PopupEvent.hideAny()
      : marker = null,
        markers = null,
        action = PopupEventActions.hideAny;

  PopupEvent.toggle(this.marker)
      : markers = null,
        action = PopupEventActions.toggle;

  PopupEvent.show(this.marker)
      : markers = null,
        action = PopupEventActions.show;
}
