/// A client built without an `AtKeysIo` performs ZERO PQ writes at startup —
/// and still gets the era read providers.
///
/// This is the property that protects the long-lived cicd atServers: the e2e
/// pack's non-PQ tests build clients through `setCurrentAtSign` with no
/// `AtKeysIo`, and the split between PQ and non-PQ test files is sufficient
/// on its own ONLY because such a client writes nothing PQ — no signing-root
/// mint, no `_apsk` publish, no advertisement, no envelope. An immutable root
/// or a published nskey on a real atSign is permanent, so a regression here
/// poisons infrastructure, not a test run.
///
/// The read half matters equally: inert does not mean blind. A client with no
/// key source must still ROUTE records other clients wrote — the era default
/// registers the nskey read providers regardless — or every mixed deployment
/// splits into clients that can write and clients that cannot read them.
///
/// The startup filer is fire-and-forget with no completion handle and, with
/// no AtKeysIo, no terminal wire marker either — so the test waits for wire
/// quiescence rather than a specific event.
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

/// Captures every log line, so the test can wait on the terminal step's own
/// message instead of guessing at wire quiescence — a keyless start may emit
/// no wire events at all, and a fixed sleep says nothing about whether the
/// chain had finished when the assertion ran.
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
    // Each test file runs in its own isolate, so no production logger exists
    // yet; every one constructed from here on adopts this handler.
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

  /// Waits until the startup chain's LAST step has spoken: the privileged
  /// anchoring sweep either skips (one of its "Not sweeping" log lines) or
  /// proceeds (its enroll:list wire command — the regression path, whose
  /// writes the assertions then catch). Fails at [timeout] with everything
  /// observed.
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
      AtClientPreference()
        ..hiveStoragePath = storageDir
        ..commitLogPath = '$storageDir/commit',
      remoteSecondary: buildRecordingRemote(
          events: events, remoteData: remoteData, remoteMeta: remoteMeta),
      atChops: AtChopsImpl(AtChopsKeys.create(
          AtChopsUtil.generateAtEncryptionKeyPair(),
          AtChopsUtil.generateAtPkamKeyPair())),
      // Deliberately NO atKeysIo — the shape every non-PQ e2e client has.
    );
    await untilStartupChainDone();

    expect(events.where((e) => e.startsWith('update:')), isEmpty,
        reason: 'a keyless client minted or published PQ state at startup — '
            'on a long-lived atSign an immutable root or a published nskey '
            'is permanent. Events:\n${events.join('\n')}');
    expect(events.where((e) => e.startsWith('delete:')), isEmpty,
        reason: 'a keyless client deleted remote state at startup. '
            'Events:\n${events.join('\n')}');
    expect(remoteData, isEmpty,
        reason: 'the atServer fixture should hold exactly what it started '
            'with: nothing');

    // Inert is not blind: the era default still registers the read
    // providers, so records other clients wrote route to a provider that
    // knows how to refuse-or-read them, rather than falling through as
    // legacy ciphertext.
    final config = CryptoConfig.forClient(client);
    expect(config.lookup(nskeyCryptoProviderId), isNotNull);
    expect(config.lookup(mlKemNskeyCryptoProviderId), isNotNull);
    expect(config.lookup(symmetricAesGcmCryptoProviderId), isNotNull);
    expect(config.defaultProviderId, legacyCryptoProviderId,
        reason: 'reads route by the record\'s own stamp; the era default '
            'only decides what NEW writes use, and in 3.x that is legacy');
  });
}
