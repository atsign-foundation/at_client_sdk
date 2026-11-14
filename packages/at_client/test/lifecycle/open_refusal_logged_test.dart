import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator, AtLookupMuxable;
import 'package:at_utils/at_utils.dart' show LoggingHandler;
import 'package:test/test.dart';

import '../test_utils/hive_store.dart';
import '../test_utils/transport.dart';

/// Every record logged through it, kept with its error and stack trace.
class _KeptLogs implements LoggingHandler {
  final List<dynamic> records = [];

  @override
  void call(dynamic record) => records.add(record);
}

/// What a store's read threw: its text's first line says why, and its
/// second holds what was read.
class _ReadRefusal implements Exception {
  _ReadRefusal(this.read);

  final String read;

  @override
  String toString() => 'the store refused\n$read';
}

/// A keys store with no path whose read throws [error].
class _RefusingStore extends WrittenAtKeysIo {
  _RefusingStore(this.error);

  final Object error;

  @override
  FutureOr<AtKeys> read(String atsign) => throw error;

  @override
  String describeSource(String atsign) => 'the test keys store';

  @override
  Future write(String atsign, AtKeys atKeys) async {}
}

/// `Atsign.open` logs its refusal of keys at fine with the read's stack
/// trace, and logs none of what the read threw.
void main() {
  const atSign = '@alice';
  final logs = _KeptLogs();
  late Directory dir;

  setUpAll(() {
    // NOTE: before open first logs; a logger binds the handler and the level
    // it finds.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'finest';
  });

  setUp(() => dir = Directory.systemTemp.createTempSync('open_refusal_'));

  tearDown(() => dir.deleteSync(recursive: true));

  AtLookupMuxable noConnection(
          {required String atSign,
          required AtRootDomain rootDomain,
          required AtAuthenticator? authenticator,
          SecondaryAddressFinder? secondaryAddressFinder}) =>
      throw StateError('no connection was expected for $atSign');

  test(
      'the refusal is logged at fine with its trace, and none of what was read',
      () async {
    const read = 'c2VjcmV0LWtleS1tYXRlcmlhbC10aGF0LXdhcy1yZWFk';
    final pref = AtClientPreference()
      ..rootDomain = InternetAddress.loopbackIPv4.address
      ..rootPort = 1
      ..hiveStoragePath = dir.path;

    Object? thrown;
    try {
      await Atsign(atSign).open(
          keys: _RefusingStore(_ReadRefusal(read)),
          preference: pref,
          lookUps: noConnection,
          secondaryAddressFinder: defaultAtDirectory,
          storage: hiveStoreFor(atSign, pref));
    } catch (e) {
      thrown = e;
    }

    expect(
        thrown,
        isA<AtKeysUnusableException>().having((e) => e.message, 'message',
            endsWith('could not be read: the store refused.')));
    final fine = logs.records.where((r) =>
        '${r.level.name}' == 'FINE' &&
        r.message == (thrown as AtKeysUnusableException).message);
    expect(fine, hasLength(1), reason: 'the refusal is logged at fine');
    expect(fine.single.stackTrace, isNotNull, reason: 'with the read\'s trace');
    for (final record in logs.records) {
      expect('${record.message}\n${record.error}\n${record.stackTrace}',
          isNot(contains(read)),
          reason: 'no record holds what was read');
    }
  });
}
