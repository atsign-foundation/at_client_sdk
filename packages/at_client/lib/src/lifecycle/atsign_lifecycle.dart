import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/at_client_factory.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/lifecycle/at_connection.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;

/// The verbs an application reaches a working client through, on the atSign
/// it holds keys for.
///
/// ```dart
/// final client = await Atsign('@alice').open(
///     keys: FileAtKeysIo(), preference: AtClientPreference());
/// client.connection.current;          // online, offline or refused
/// client.connection.changes.listen((state) { ... });
/// AtClientManager.getInstance().use(client);
/// ```
extension AtsignLifecycle on Atsign {
  /// Builds a client for this atSign from [keys], tries once to reach the
  /// atServer within [connectBudget], and hands the client back with
  /// `connection.current` saying how that went. The caller owns the client
  /// and ends it with `stop()`.
  ///
  /// The client comes back whether the atServer was reached or not: offline
  /// it serves everything its local storage holds, and `connection.changes`
  /// reports when that changes. The one exception is the first open of a
  /// principal on a device: with nothing held locally for these keys, a
  /// refusal (revoked, unauthenticated, an expired or unapproved enrollment,
  /// or an atSign the atDirectory has no atServer for) throws
  /// [AtOpenRefusedException] and nothing is handed back, since there would
  /// be nothing for the client to serve. Once a principal has been online on
  /// a device, a refusal comes back as a client in the `refused` state and
  /// the application decides.
  ///
  /// [namespace] defaults to the preference's. [storage] is the client's
  /// local storage, borrowed unless it was built with `closedByClient: true`;
  /// with none, a Hive store opens under `preference.hiveStoragePath`.
  /// [atLookUp] is a connection to use instead of one built from the
  /// preference, for a caller that already holds one.
  ///
  /// Refuses, as `buildAtClient` does, while a client for this atSign is
  /// live in this process.
  Future<AtClient> open({
    required AtKeysIo keys,
    required AtClientPreference preference,
    String? namespace,
    AtClientStorage? storage,
    AtLookUp? atLookUp,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async {
    final client = await buildAtClient(
      atSign: this,
      namespace: namespace ?? preference.namespace,
      preference: preference,
      storage: storage,
      atKeysIo: keys,
      atLookUp: atLookUp,
    ) as AtClientImpl;

    final state = await client.connection.attempt(budget: connectBudget);
    final refusesFirstOpen =
        state.isRefused || state.cause == AtConnectionCause.noAtServer;
    if (refusesFirstOpen && !await client.hasBeenOnline()) {
      await client.stop();
      throw AtOpenRefusedException(this, state);
    }
    return client;
  }
}
