// ignore_for_file: prefer_const_constructors_in_immutables, no_logic_in_create_state

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_controller.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_builder.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_event.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_event_actions.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_position.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_snap.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/layer/marker_layer.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/map/map.dart';

class MarkerPopup extends StatefulWidget {
  final PopupController? popupController;
  final PopupBuilder? popupBuilder;
  final PopupSnap snap;
  final MapState? mapState;

  MarkerPopup({
    required this.mapState,
    required this.popupController,
    required this.snap,
    required this.popupBuilder,
    Key? key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _MarkerPopupState(
      mapState,
      popupController,
      snap,
      popupBuilder,
    );
  }
}

class _MarkerPopupState extends State<MarkerPopup> {
  final MapState? _mapState;
  final PopupController? _popupController;
  final PopupBuilder? _popupBuilder;
  final PopupSnap _snap;

  UniqueKey? _popupKey; // Changing forces child rebuild.
  Marker? _selectedMarker;

  _MarkerPopupState(
    this._mapState,
    this._popupController,
    this._snap,
    this._popupBuilder,
  );

  @override
  void initState() {
    super.initState();

    _popupController!.streamController =
        StreamController<PopupEvent>.broadcast();
    _popupController!.streamController!.stream
        .listen((PopupEvent popupEvent) => _handleAction(popupEvent));
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedMarker == null) return Container();

    final popupContainer =
        PopupPosition.container(_mapState!, _selectedMarker!, _snap);

    return Positioned(
      width: popupContainer.width,
      height: popupContainer.height,
      left: popupContainer.left,
      top: popupContainer.top,
      right: popupContainer.right,
      bottom: popupContainer.bottom,
      child: Align(
        alignment: popupContainer.alignment!,
        child: Builder(
          key: _popupKey,
          builder: (context) => _popupBuilder!(context, _selectedMarker),
        ),
      ),
    );
  }

  void _handleAction(PopupEvent event) {
    switch (event.action) {
      case PopupEventActions.hideAny:
        return _hideAny();
      case PopupEventActions.hideInList:
        return _hideInList(event.markers!);
      case PopupEventActions.toggle:
        return _toggle(event.marker);
      case PopupEventActions.show:
        return _showForMarker(event.marker);
    }
  }

  void _hideAny() {
    if (_selectedMarker != null) {
      setState(() {
        _popupKey = null;
        _selectedMarker = null;
      });
    }
  }

  void _showForMarker(Marker? marker) {
    if (marker != null && _selectedMarker != marker) {
      setState(() {
        _popupKey = UniqueKey();
        _selectedMarker = marker;
      });
    }
  }

  void _hideInList(List<Marker?> markers) {
    if (markers.contains(_selectedMarker)) _hideAny();
  }

  void _toggle(Marker? marker) {
    if (marker != null) {
      _selectedMarker == marker ? _hideAny() : _showForMarker(marker);
    }
  }

  @override
  void dispose() {
    _popupController!.streamController!.close();
    super.dispose();
  }
}
