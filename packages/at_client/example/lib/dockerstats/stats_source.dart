/// Abstract source of [StatSample]s. Backed in production by the docker
/// CLI ([DockerCliStatsSource]); in [SimulatedStatsSource] mode, by a
/// bounded random walk over a fixed set of fake hosts and atSigns.
library;

import 'dart:async';

import 'models.dart';

abstract class StatsSource {
  /// Hostname this source is reporting for. For the docker source it's
  /// the local machine; for simulate mode it's a synthetic host name
  /// (the simulator returns multiple `StatsSource`s, one per fake host).
  String get hostname;

  /// One polling cycle's worth of samples — one [StatSample] per
  /// container the source can see at this instant. Empty list if no
  /// containers exist.
  Future<List<StatSample>> sample();
}
