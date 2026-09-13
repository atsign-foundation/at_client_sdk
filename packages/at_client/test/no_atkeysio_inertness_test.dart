/// A client built without an `AtKeysIo` performs ZERO PQ writes at startup —
/// and still gets the era read providers.
///
/// The write half protects long-lived atServers: a keyless client mints no
/// signing root, publishes no `_apsk`, advertises nothing and seals no
/// envelope. A signing root or a published nskey on a real atSign outlives
/// the run that wrote it, so a regression here poisons infrastructure rather
/// than a test run.
///
/// The read half matters equally — inert does not mean blind. A client with no
/// key source must still ROUTE records other clients wrote, or every mixed
/// deployment splits into clients that can write and clients that cannot read
/// them.
library;

import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/recording_remote.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Captures every log line, so the test can wait on the terminal startup
/// step's own message: a keyless start may emit no wire events at all.
class _CapturingLogHandler implements LoggingHandler {
  final List<String> messages = [];

  @override
  void call(record) {
    messages.add(record.message);
    AtSignLogger.consoleLoggingHandler.call(record);
  }
}

void main() {
  const atSign = '@alice';
  const storageDir = 'test/hive/no_atkeysio';

  late List<String> events;
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMeta;
  final log = _CapturingLogHandler();

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    // NOTE: only loggers constructed after this adopt the handler; the file's
    // own isolate means none exists yet.
    AtSignLogger.defaultLoggingHandler = log;
  });

  setUp(() {
    events = [];
    remoteData = {};
    remoteMeta = {};
    AtClientImpl.atClientInstanceMap.clear();
  });

  tearDown(() async {
    try {
      await Hive.close();
      AtClientImpl.atClientInstanceMap.clear();
      final dir = Directory(storageDir);
      if (await dir.exists()) dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Waits until the startup chain's last step has spoken — the privileged
  /// anchoring sweep either skipping or issuing its `enroll:list`. Fails at
  /// [timeout] with everything observed.
  Future<void> untilStartupChainDone(
      {Duration timeout = const Duration(seconds: 15)}) async {
    final deadline = DateTime.now().add(timeout);
    bool done() =>
        log.messages.any((m) => m.contains('Not sweeping')) ||
        log.messages.any((m) => m.contains('The chain sweep failed')) ||
        events.any((e) => e.startsWith('cmd:enroll:list'));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the startup chain never reached its final step within '
            '$timeout.\nEvents:\n${events.join('\n')}\n'
            'Logs:\n${log.messages.join('\n')}');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a start with no AtKeysIo writes nothing to the atServer', () async {
    final client = await AtClientImpl.create(
      atSign,
      'buzz',
      // NOTE: `pqReady` is what keeps this test non-vacuous — the default
      // posture runs no post-quantum startup at all, so the client would be
      // inert whether or not the absent AtKeysIo mattered.
      AtClientPreference(posture: PqPosture.pqReady)
        ..hiveStoragePath = storageDir
        ..commitLogPath = '$storageDir/commit',
      remoteSecondary: buildRecordingRemote(
          events: events, remoteData: remoteData, remoteMeta: remoteMeta),
      atChops: AtChopsImpl(AtChopsKeys.create(
          AtChopsUtil.generateAtEncryptionKeyPair(),
          AtChopsUtil.generateAtPkamKeyPair())),
      // Deliberately NO atKeysIo — its absence is the property under test.
    );
    await untilStartupChainDone();

    expect(events.where((e) => e.startsWith('update:')), isEmpty,
        reason: 'a keyless client minted or published PQ state at startup — '
            'on a long-lived atSign a signing root or a published nskey '
            'outlives the run, and this would also catch a mint lock taken '
            'where no mint belongs. Events:\n${events.join('\n')}');
    expect(events.where((e) => e.startsWith('delete:')), isEmpty,
        reason: 'a keyless client deleted remote state at startup. '
            'Events:\n${events.join('\n')}');
    expect(remoteData, isEmpty,
        reason: 'the atServer fixture should hold exactly what it started '
            'with: nothing');

    final config = CryptoConfig.forClient(client);
    expect(config.lookup(nskeyCryptoProviderId), isNotNull);
    expect(config.lookup(mlKemNskeyCryptoProviderId), isNotNull);
    expect(config.lookup(symmetricAesGcmCryptoProviderId), isNotNull);
    expect(config.defaultProviderId, legacyCryptoProviderId,
        reason: 'reads route by the record\'s own stamp; the era default '
            'only decides what NEW writes use, and in 3.x that is the legacy provider');
  });
}
