import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

/// Implementation for storing CryptoKeys inside of the AtSecondary (at_server)
class CryptoSecondaryStorage implements CryptoStorage {
  final AtClient _atClient;

  CryptoSecondaryStorage(this._atClient);

  Future<String?> readLocal(CryptoStorageKey key) {
    return _read(_atClient.getLocalSecondary(), key);
  }

  Future<void> writeLocal(CryptoStorageKey key, String value) {
    return _write(_atClient.getLocalSecondary(), key, value);
  }

  /// Read CryptoStorageKey from remote secondary
  @override
  Future<String?> read(CryptoStorageKey key) {
    return _read(_atClient.getRemoteSecondary(), key);
  }

  /// Write CryptoStorageKey from remote secondary
  @override
  Future<void> write(CryptoStorageKey key, String value) {
    return _write(_atClient.getRemoteSecondary(), key, value);
  }

  Future<String?> _read(Secondary? secondary, CryptoStorageKey key) async {
    if (secondary == null) {
      return null;
    }
    final result = await secondary.executeVerb(
      LookupVerbBuilder()..atKey = _toAtKey(key),
    );
    if (result == null || result == 'data:null') {
      return null;
    }
    return DefaultResponseParser().parse(result).response;
  }

  Future<void> _write(
    Secondary? secondary,
    CryptoStorageKey key,
    String value,
  ) async {
    if (secondary == null) {
      return;
    }
    await secondary.executeVerb(
      UpdateVerbBuilder()
        ..atKey = _toAtKey(key)
        ..value = value,
      sync: false,
    );
  }

  AtKey _toAtKey(CryptoStorageKey key) {
    final namespace = key.namespace.trim();
    final name = namespace.isEmpty ? key.name : '${key.name}.$namespace';
    return AtKey()
      ..key = '$name.${key.recipient.replaceAll('@', '')}'
      ..sharedBy = key.owner
      ..sharedWith = key.recipient;
  }
}
