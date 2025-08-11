import 'dart:math';
import 'package:flutter/material.dart';
import 'package:at_location_flutter/map_content/flutter_map/flutter_map.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_builder.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_controller.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_popup/src/popup_snap.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_cluster/src/node/marker_cluster_node.dart';

class PolygonOptions {
  final Color color;
  final double borderStrokeWidth;
  final Color borderColor;
  final bool isDotted;

  const PolygonOptions({
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.isDotted = false,
  });
}

class AnimationsOptions {
  final Duration zoom;
  final Duration fitBound;
  final Curve fitBoundCurves;
  final Duration centerMarker;
  final Curve centerMarkerCurves;
  final Duration spiderfy;

  const AnimationsOptions({
    this.zoom = const Duration(milliseconds: 500),
    this.fitBound = const Duration(milliseconds: 500),
    this.centerMarker = const Duration(milliseconds: 500),
    this.spiderfy = const Duration(milliseconds: 500),
    this.fitBoundCurves = Curves.fastOutSlowIn,
    this.centerMarkerCurves = Curves.fastOutSlowIn,
  });
}

class PopupOptions {
  final PopupBuilder? popupBuilder;
  final PopupController? popupController;
  final PopupSnap popupSnap;

  const PopupOptions({
    this.popupBuilder,
    this.popupSnap = PopupSnap.top,
    this.popupController,
  });
}

typedef ClusterWidgetBuilder = Widget Function(
    BuildContext context, List<Marker?> markers);

class MarkerClusterLayerOptions extends LayerOptions {
  /// Cluster builder
  final ClusterWidgetBuilder builder;

  /// List of markers
  final List<Marker?> markers;

  /// Cluster size
  final Size size;

  /// Cluster compute size
  final Size Function(List<Marker?>)? computeSize;

  /// Cluster anchor
  final AnchorPos? anchor;

  /// A cluster will cover at most this many pixels from its center
  final int maxClusterRadius;

  /// Options for fit bounds
  final FitBoundsOptions fitBoundsOptions;

  /// Zoom buonds with animation on click cluster
  final bool zoomToBoundsOnClick;

  /// animations options
  final AnimationsOptions animationsOptions;

  /// When click marker, center it with animation
  final bool centerMarkerOnClick;

  /// Increase to increase the distance away that circle spiderfied markers appear from the center
  final int spiderfyCircleRadius;

  /// If set, at this zoom level and below, markers will not be clustered. This defaults to 20 (max zoom)
  final int disableClusteringAtZoom;

  /// Increase to increase the distance away that spiral spiderfied markers appear from the center
  final int spiderfySpiralDistanceMultiplier;

  /// Show spiral instead of circle from this marker count upwards.
  /// 0 -> always spiral; Infinity -> always circle
  final int circleSpiralSwitchover;

  /// Make it possible to provide custom function to calculate spiderfy shape positions
  final List<Point> Function(int, Point)? spiderfyShapePositions;

  /// If true show polygon then tap on cluster
  final bool showPolygon;

  /// Polygon's options that shown when tap cluster.
  final PolygonOptions polygonOptions;

  /// Function to call when a Marker is tapped
  final void Function(Marker?)? onMarkerTap;

  /// Function to call when markers are clustered
  final void Function(List<Marker?>)? onMarkersClustered;

  /// Function to call when a cluster Marker is tapped
  final void Function(MarkerClusterNode)? onClusterTap;

  /// Popup's options that show when tapping markers or via the PopupController.
  final PopupOptions? popupOptions;

  MarkerClusterLayerOptions({
    required this.builder,
    this.markers = const [],
    this.size = const Size(30, 30),
    this.computeSize,
    this.anchor,
    this.maxClusterRadius = 80,
    this.disableClusteringAtZoom = 20,
    this.animationsOptions = const AnimationsOptions(),
    this.fitBoundsOptions =
        const FitBoundsOptions(padding: EdgeInsets.all(12.0)),
    this.zoomToBoundsOnClick = true,
    this.centerMarkerOnClick = true,
    this.spiderfyCircleRadius = 40,
    this.spiderfySpiralDistanceMultiplier = 1,
    this.circleSpiralSwitchover = 9,
    this.spiderfyShapePositions,
    this.polygonOptions = const PolygonOptions(),
    this.showPolygon = true,
    this.onMarkerTap,
    this.onClusterTap,
    this.onMarkersClustered,
    this.popupOptions,
    // ignore: unnecessary_null_comparison
  }) : assert(builder != null);
}
