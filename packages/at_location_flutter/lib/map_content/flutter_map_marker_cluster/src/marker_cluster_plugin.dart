import 'package:flutter/material.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/layer/layer.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/map/map.dart';
import 'package:at_location_flutter/map_content/flutter_map/src/plugins/plugin.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_cluster/src/marker_cluster_layer.dart';
import 'package:at_location_flutter/map_content/flutter_map_marker_cluster/src/marker_cluster_layer_options.dart';

class MarkerClusterPlugin extends MapPlugin {
  final Key key;
  MarkerClusterPlugin(this.key);
  @override
  Widget createLayer(
      LayerOptions options, MapState? mapState, Stream<void> stream) {
    return MarkerClusterLayer(
        options as MarkerClusterLayerOptions, mapState, stream, key);
  }

  @override
  bool supportsLayer(LayerOptions options) {
    return options is MarkerClusterLayerOptions;
  }
}
