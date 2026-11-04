import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';
import 'package:at_utils/at_utils.dart';

/// A Hive store for [atSign] under [preference]'s `hiveStoragePath`, closed
/// by the client that holds it when it stops.
AtClientStorage hiveStoreFor(String atSign, AtClientPreference preference) =>
    // ignore: deprecated_member_use
    hiveStoreAt(atSign, preference.hiveStoragePath!);

/// A Hive store for [atSign] under [storagePath], closed by the client that
/// holds it when it stops.
AtClientStorage hiveStoreAt(String atSign, String storagePath) =>
    HiveAtClientStorage(
        atSign: AtUtils.fixAtSign(atSign).toAtsign(),
        storagePath: storagePath,
        closedByClient: true);
