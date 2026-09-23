import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/sync/sync_queue_store.dart';

const _noDefault = 'There is no default storage on the web; pass storage: '
    '(e.g. RemoteOnlyAtClientStorage)';

/// Throws: the web has no default backend.
AtClientStorage defaultAtClientStorage(
        {required String atSign,
        required String storagePath,
        bool closedByClient = false}) =>
    throw StateError(_noDefault);

/// Always null: the web has no default backend.
String? defaultStorageLocation(
        {required String atSign, required String storagePath}) =>
    null;

/// Always false: the web has no default backend.
bool isDefaultStorage(AtClientStorage storage) => false;

/// Throws: the web has no default backend.
Future<SyncQueueStore> defaultSyncQueueStore(
        {required String atSign, String? storagePath}) =>
    throw StateError(_noDefault);
