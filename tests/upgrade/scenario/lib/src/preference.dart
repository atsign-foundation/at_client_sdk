// `hiveStoragePath` and `commitLogPath` are deprecated in the current tree and
// are how a 3.14.0 app names its store, so code shared with that version has
// only these spellings.
// ignore_for_file: deprecated_member_use

import 'package:at_client/at_client.dart' show AtClientPreference;
import 'package:pq_matrix_scenario/connect.dart' show ClientSpec;

/// The preference an app written against the oldest covered at_client sets,
/// so an upgrade changes the library and nothing else.
AtClientPreference upgradePreference(ClientSpec spec) => AtClientPreference()
  ..hiveStoragePath = spec.storagePath
  ..commitLogPath = spec.storagePath
  ..rootDomain = spec.rootDomain
  ..rootPort = spec.rootPort
  ..namespace = spec.namespace
  ..fetchOfflineNotifications = true;
