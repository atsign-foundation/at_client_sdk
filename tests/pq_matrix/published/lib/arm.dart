import 'package:at_client/at_client.dart' show AtClientPreference;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart' show ClientSpec;

/// The control arm's preference: every field a 3.14.0 app would set, and
/// nothing else.
///
/// [stage] is ignored, and there is nothing here it could select.
/// `PqPosture` does not exist in at_client 3.14.0 — this arm has no knob
/// to turn, which is exactly what makes it a measurement of the released build
/// rather than a simulation of one. The parameter stays so the two arms
/// present one shape to the shared entrypoint.
AtClientPreference publishedPreference(ClientSpec spec, String stage) =>
    AtClientPreference()
      ..hiveStoragePath = spec.storagePath
      ..commitLogPath = spec.storagePath
      ..rootDomain = spec.rootDomain
      ..rootPort = spec.rootPort
      ..namespace = spec.namespace
      ..decryptPackets = false
      ..tlsKeysSavePath = '${spec.storagePath}/tlsKeys'
      ..fetchOfflineNotifications = true;
