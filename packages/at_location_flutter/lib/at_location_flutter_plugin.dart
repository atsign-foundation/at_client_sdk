import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_location_flutter/common_components/custom_toast.dart';
import 'package:at_location_flutter/location_modal/hybrid_model.dart';
import 'package:at_location_flutter/service/location_service.dart';
import 'package:at_location_flutter/show_location.dart';
import 'package:at_location_flutter/utils/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:at_location_flutter/map_content/flutter_map/flutter_map.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_cluster/src/marker_cluster_layer_options.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_cluster/src/marker_cluster_plugin.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_controller.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_snap.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'common_components/floating_icon.dart';
import 'common_components/marker_cluster.dart';
import 'common_components/popup.dart';
import 'package:at_utils/at_logger.dart';

/// A class defined to show markers based on current location of mentioned atsigns.
// ignore: must_be_immutable
class AtLocationFlutterPlugin extends StatefulWidget {
  /// Atsigns whose location needs to be shown.
  final List<String?>? atsignsToTrack;

  /// Padding for the markers.
  double? left, right, top, bottom;

  /// ETA will be calculated from this co-ordinate.
  LatLng? etaFrom;

  /// [textForCenter] Text for the co-ordinate from where ETA is calculated.
  ///
  /// [focusMapOn] Atsign of user whom to focus on.
  String? textForCenter, focusMapOn;

  /// [calculateETA] if ETA needs to be calculated/displayed.
  /// [addCurrentUserMarker] if logged in users current location should be added to the map.
  bool calculateETA, addCurrentUserMarker;

  /// needed to track details of a specific notification (event/p2p).
  String? notificationID;

  /// needed if we want to check for location data after a particular time
  DateTime? refreshAt;

  AtLocationFlutterPlugin(
    this.atsignsToTrack, {
    Key? key,
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.calculateETA = false,
    this.addCurrentUserMarker = false,
    this.textForCenter = 'Centre',
    this.etaFrom,
    this.focusMapOn,
    this.notificationID,
    this.refreshAt,
  }) : super(key: key);

  @override
  _AtLocationFlutterPluginState createState() =>
      _AtLocationFlutterPluginState();
}

class _AtLocationFlutterPluginState extends State<AtLocationFlutterPlugin> {
  final _logger = AtSignLogger('AtLocationFlutterPlugin');

  PanelController pc = PanelController();
  PopupController _popupController = PopupController();
  MapController? mapController;
  List<LatLng?>? points;
  bool isEventAdmin = false;
  late bool showMarker, mapAdjustedOnce;
  BuildContext? globalContext;

  // ignore: prefer_final_fields
  Key _mapKey = UniqueKey();

  List<String> atsignsCurrentlySharing = [];

  @override
  void initState() {
    super.initState();
    showMarker = true;
    mapAdjustedOnce = false;
    atsignsCurrentlySharing = [];

    mapController = MapController();
    LocationService().init(widget.atsignsToTrack,
        etaFrom: widget.etaFrom,
        calculateETA: widget.calculateETA,
        addCurrentUserMarker: widget.addCurrentUserMarker,
        textForCenter: widget.textForCenter,
        showToast: showToast,
        notificationID: widget.notificationID,
        refreshAt: widget.refreshAt);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      LocationService().mapInitialized();
      LocationService().notifyListeners();
    });
  }

  void showToast(String msg, {bool isError = false, isSuccess = false}) {
    if (globalContext != null) {
      CustomToast()
          .show(msg, globalContext!, isError: isError, isSuccess: isSuccess);
    }
  }

  @override
  void dispose() {
    LocationService().dispose();
    _popupController.streamController?.close();
    super.dispose();
  }

  /// Calculates the list of currently sharing @signs based on the provided user data
  calculateAtsignsCurrentlySharing(List<HybridModel?> users) {
    List<String> _newAtsignsSharing = [], _atsignsStoppedSharing = [];
    for (var _user in users) {
      if (_user == null) {
        continue;
      }
      if ((_user.displayName !=
              AtClientManager.getInstance().atClient.getCurrentAtSign()) &&
          ((LocationService().centreMarker == null) ||
              (_user.displayName !=
                  LocationService().centreMarker?.displayName))) {
        if (!atsignsCurrentlySharing.contains(_user.displayName)) {
          atsignsCurrentlySharing.add(_user.displayName!);
          _newAtsignsSharing.add(_user.displayName!);
        }
      }
    }

    atsignsCurrentlySharing.removeWhere((element) {
      var _res =
          users.indexWhere((_user) => _user?.displayName == element) == -1;
      if ((_res) && (!_atsignsStoppedSharing.contains(element))) {
        _atsignsStoppedSharing.add(element);
      }
      return _res;
    });

    if (_newAtsignsSharing.isNotEmpty) {
      CustomToast().show(
          '${_listToString(_newAtsignsSharing)} started sharing location',
          globalContext!,
          isError: false,
          isSuccess: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    globalContext = context;

    return Scaffold(
        body: SafeArea(
      child: Stack(
        children: [
          StreamBuilder(
              stream: LocationService().atHybridUsersStream,
              builder: (context, AsyncSnapshot<List<HybridModel?>> snapshot) {
                if (snapshot.connectionState == ConnectionState.active) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'error',
                        style: TextStyle(fontSize: 400),
                      ),
                    );
                  } else {
                    _logger.finer('FlutterMap called');

                    _popupController = PopupController();
                    var users = snapshot.data!;
                    var markers = users.map((user) => user!.marker).toList();
                    points = users.map((user) => user!.latLng).toList();

                    _logger.finer('markers length = ${markers.length}');
                    for (var element in users) {
                      _logger.finer('displayanme - ${element!.displayName}');
                    }
                    for (var element in markers) {
                      _logger.finer('point - ${element!.point}');
                    }

                    calculateAtsignsCurrentlySharing(users);

                    try {
                      if (widget.focusMapOn == null) {
                        if ((!mapAdjustedOnce) &&
                            (markers.isNotEmpty) &&
                            (mapController != null)) {
                          mapController!.move(markers[0]!.point, 10);
                          mapAdjustedOnce = true;
                        }
                      } else {
                        if ((!mapAdjustedOnce) &&
                            (markers.isNotEmpty) &&
                            (mapController != null)) {
                          var indexOfUser = users.indexWhere((element) =>
                              element!.displayName == widget.focusMapOn);

                          if (indexOfUser > -1) {
                            mapController!
                                .move(markers[indexOfUser]!.point, 10);

                            /// If we want the map to only update once
                            /// And not keep the focus on user sharing his location
                            /// then uncomment
                            //
                            mapAdjustedOnce = true;
                          } else if (!mapAdjustedOnce) {
                            /// It moves the focus to logged in user,
                            /// when other user is not sharing location
                            mapController!.move(markers[0]!.point, 10);
                            mapAdjustedOnce = true;
                          }
                        }
                      }
                    } catch (e) {
                      _logger.severe('$e');
                    }

                    return FlutterMap(
                      key: _mapKey,
                      mapController: mapController,
                      options: MapOptions(
                        boundsOptions: FitBoundsOptions(
                            padding: EdgeInsets.fromLTRB(
                          widget.left ?? 20,
                          widget.top ?? 20,
                          widget.right ?? 20,
                          widget.bottom ?? 20,
                        )),
                        // ignore: unnecessary_null_comparison
                        center: ((users != null) && (users.isNotEmpty))
                            ? users[0]!.latLng
                            : const LatLng(45, 45),
                        zoom: markers.isNotEmpty ? 8 : 2,
                        plugins: [MarkerClusterPlugin(UniqueKey())],
                        onTap: (_) => _popupController
                            .hidePopup(), // Hide popup when the map is tapped.
                      ),
                      layers: [
                        TileLayerOptions(
                          minNativeZoom: 2,
                          maxNativeZoom: 18,
                          minZoom: 2,
                          urlTemplate:
                              'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=${MixedConstants.MAP_KEY}',
                        ),
                        MarkerClusterLayerOptions(
                          maxClusterRadius: 190,
                          disableClusteringAtZoom: 16,
                          size: showMarker
                              ? ((markers.length > 1)
                                  ? const Size(200, 150)
                                  : const Size(5, 5))
                              : const Size(0, 0),
                          anchor: AnchorPos.align(AnchorAlign.center),
                          fitBoundsOptions: const FitBoundsOptions(
                            padding: EdgeInsets.all(50),
                          ),
                          markers: showMarker ? markers : [],
                          polygonOptions: const PolygonOptions(
                              borderColor: Colors.blueAccent,
                              color: Colors.black12,
                              borderStrokeWidth: 3),
                          popupOptions: PopupOptions(
                              popupSnap: PopupSnap.top,
                              popupController: _popupController,
                              popupBuilder: (_, marker) {
                                return _popupController
                                        .streamController!.isClosed
                                    ? const Text('Closed')
                                    : buildPopup(snapshot
                                        .data![markers.indexOf(marker)]!);
                              }),
                          builder: (context, markers) {
                            return buildMarkerCluster(markers,
                                eventData: LocationService().centreMarker);
                          },
                        ),
                      ],
                    );
                  }
                } else {
                  return showLocation(UniqueKey(), mapController);
                }
              }),
          Positioned(
            top: 100,
            right: 0,
            child: FloatingIcon(icon: Icons.zoom_out_map, onPressed: zoomOutFn),
          ),
        ],
      ),
    ));
  }

  /// Zooms out the map and hides the popup
  void zoomOutFn() {
    _popupController.hidePopup();
    if (LocationService().hybridUsersList.isNotEmpty) {
      mapController!.move(LocationService().hybridUsersList[0]!.latLng, 4);
    }
  }

  /// Converts a list of strings to a single string
  String? _listToString(List _strings) {
    String? _res;
    if (_strings.isNotEmpty) {
      _res = _strings[0];
    }

    _strings.sublist(1).forEach((element) {
      _res = '$_res, $element';
    });

    return _res;
  }
}
