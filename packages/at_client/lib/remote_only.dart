/// The remote-only [AtClientStorage] implementation — no local database,
/// every read/write a round trip to the atServer. A separate import so
/// `package:at_client/at_client.dart` carries no Hive/SQLite dependency.
///
/// Also exports [NotificationServiceImpl], which a client composed without
/// `AtClientManager` constructs for itself.
library;

export 'package:at_client/src/service/notification_service_impl.dart'
    show NotificationServiceImpl;
export 'package:at_client/src/storage/remote_only_at_client_storage.dart';
