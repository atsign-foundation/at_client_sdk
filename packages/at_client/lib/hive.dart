/// The Hive-backed [AtClientStorage], which a client opens when it is given no
/// storage until 4.0. A separate import, like each storage backend, so an app
/// names the backend it chooses.
library;

export 'package:at_client/src/storage/hive/hive_at_client_storage.dart';
