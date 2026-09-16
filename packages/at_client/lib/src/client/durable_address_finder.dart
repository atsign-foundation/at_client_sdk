import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';

/// The atServer address, remembered in the client's own storage once the
/// atDirectory has answered, so a start that cannot reach the atDirectory
/// still knows where the atServer is.
///
/// Wraps the finder the process would otherwise use, resolved per lookup so
/// one registered later is still found. A lookup for any atSign but
/// [atSign] passes straight through: only this client's own atServer is
/// remembered. The atDirectory answering that the atSign has no atServer is
/// an answer, not an outage, and is never masked by a remembered address.
class DurableSecondaryAddressFinder implements SecondaryAddressFinder {
  final String atSign;
  final SecondaryAddressFinder Function() _inner;
  final Future<String?> Function() _read;
  final Future<void> Function(String record) _write;
  final AtSignLogger _logger;
  String? _lastRecord;

  /// [read] and [write] are the durable slot the address is kept in, as the
  /// JSON record [recordFor] builds; [read] answers null when it holds none.
  DurableSecondaryAddressFinder(
    String atSign, {
    required SecondaryAddressFinder Function() inner,
    required Future<String?> Function() read,
    required Future<void> Function(String record) write,
  })  : atSign = AtUtils.fixAtSign(atSign),
        _inner = inner,
        _read = read,
        _write = write,
        _logger = AtSignLogger('DurableSecondaryAddressFinder ($atSign)');

  /// The record the durable slot holds for [address].
  static String recordFor(SecondaryAddress address) => jsonEncode({
        'host': address.host,
        'port': address.port,
        'at': DateTime.now().toUtc().toIso8601String(),
      });

  /// The address a record from [recordFor] names, or null for anything else.
  static SecondaryAddress? addressIn(String? record) {
    if (record == null) return null;
    try {
      final decoded = jsonDecode(record);
      if (decoded is Map &&
          decoded['host'] is String &&
          decoded['port'] is int) {
        return SecondaryAddress(
            decoded['host'] as String, decoded['port'] as int);
      }
    } on FormatException {
      // Not a record this class wrote; nothing to remember.
    }
    return null;
  }

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    final inner = _inner();
    if (AtUtils.fixAtSign(atSign) != this.atSign) {
      return inner.findSecondary(atSign, timeout: timeout);
    }
    final SecondaryAddress found;
    try {
      found = await inner.findSecondary(atSign, timeout: timeout);
    } on SecondaryNotFoundException {
      rethrow;
    } catch (e) {
      final remembered = addressIn(await _read());
      if (remembered == null) rethrow;
      _logger.warning('the atDirectory could not be reached for $atSign ($e); '
          'using the atServer address it last gave, $remembered');
      return remembered;
    }
    await _remember(found);
    return found;
  }

  Future<void> _remember(SecondaryAddress address) async {
    final previous = addressIn(_lastRecord ??= await _read());
    if (previous != null &&
        previous.host == address.host &&
        previous.port == address.port) {
      return;
    }
    final record = recordFor(address);
    await _write(record);
    _lastRecord = record;
  }
}
