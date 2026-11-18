// `hiveStoragePath` is deprecated in the current tree and is how a 3.14.0 app
// names its store, so code shared with that version has only this spelling.
// ignore_for_file: deprecated_member_use

import 'package:at_client/at_client.dart' show AtClientPreference;
import 'package:pq_matrix_scenario/connect.dart' show ClientSpec;

/// The preference an app written against the oldest covered at_client sets,
/// so an upgrade changes the library and nothing else.
///
/// The app names itself and its version in `atClientParticulars`, as every
/// covered at_client lets it, so a client of this tree has no unnamed app to
/// warn about.
AtClientPreference upgradePreference(ClientSpec spec) => AtClientPreference()
  ..hiveStoragePath = spec.storagePath
  ..rootDomain = spec.rootDomain
  ..rootPort = spec.rootPort
  ..namespace = spec.namespace
  ..fetchOfflineNotifications = true
  ..atClientParticulars.appName = 'upgrade_scenario'
  ..atClientParticulars.appVersion = '1.0.0';
