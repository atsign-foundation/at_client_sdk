import 'dart:async';

import 'package:at_chops/at_chops.dart' show RsaKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart'
    show PqStartupGates;
import 'package:at_lookup/at_lookup.dart'
    show AtAuthenticator, AtCommandExecutor, AtLookUpFactory;
import 'package:test/test.dart';

import '../support/wire_fakes.dart';
import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/transport.dart';

/// Catalogue: features/at_client/open_budget_edge.feature
///
/// A connection attempt whose budget fires *after* the atServer answered
/// `from:` is not a statement about reachability. The atServer has spoken, so
/// the attempt must wait for the authentication's own outcome — online,
/// refused, or a local fault thrown as itself — and never report offline
/// because of the budget alone. The wire below answers the authenticator the
/// way the atServer does, and its `from:` and `pkam:` legs are timed by the
/// test.
void main() {
  const atSign = '@alice';

  late Wire wire;
  late _Edge edge;

  setUp(() {
    wire = Wire()..runsAuthenticator = true;
    edge = _Edge(wire);
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      try {
        await client.stop();
      } catch (_) {
        // Teardown: a client the test already stopped may fail again.
      }
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  /// A client whose own connection reaches the atServer through [wire], and
  /// whose authenticator is the one at_client installs from the keyfile.
  Future<AtClientImpl> clientOverWire() async {
    final keys = await keyfileHolding(atSign,
        enrollmentId: 'primary',
        encryptionKeyPair: RsaKeyPair.generate(),
        selfEncryptionKey: testSelfEncryptionKey,
        apkamKeyPair: RsaKeyPair.generate());
    return await AtClientImpl.create(
      atSign,
      'edge',
      AtClientPreference(pqStartupGates: const PqStartupGates.inert())
        ..namespace = 'edge'
        ..monitorAutoStart = false
        ..rootDomain = 'test.atsign.wtf',
      atKeysIo: keys,
      lookUps: _lookUpsOver(wire, edge),
      secondaryAddressFinder: defaultAtDirectory,
      storage: InMemoryAtClientStorage(atSign: atSign),
    ) as AtClientImpl;
  }

  test(
      'a budget that ends before the atServer\'s challenge arrives reports '
      'offline', () async {
    // The atServer never answers `from:`: nothing about the connection has
    // been learnt, so the budget is all there is to go on.
    edge.holds.add(Completer<String>());
    final client = await clientOverWire();

    final state = await client.connection
        .attempt(budget: const Duration(milliseconds: 100));

    expect(state.isOffline, isTrue, reason: '$state');
    expect(state.cause, AtConnectionCause.unreachable,
        reason: 'the challenge never arrived, so the attempt says nothing '
            'about the credentials and only the budget has an answer');
    expect(client.getRemoteSecondary()!.attemptsOpen, 0,
        reason: 'a budget that ends the attempt closes its watch');
  });

  test(
      'a budget that ends after the challenge reports the authentication\'s '
      'own outcome, not offline', () async {
    // The atServer answers `from:` at once; the `pkam:` reply lands after the
    // attempt's budget, and it succeeds.
    edge.pkamDelay = const Duration(milliseconds: 300);
    final client = await clientOverWire();

    final state = await client.connection
        .attempt(budget: const Duration(milliseconds: 100));

    expect(state.isOnline, isTrue,
        reason: '$state: the challenge arrived before the budget, so the '
            'atServer is reached and the attempt waits for the pkam: reply');
    expect(wire.pkamCommands, hasLength(1),
        reason: 'the authentication ran to its own outcome');
    expect(client.getRemoteSecondary()!.attemptsOpen, 0,
        reason: 'a finished attempt closes its watch');
  });

  test('an attempt that succeeds within its budget closes its watch', () async {
    final client = await clientOverWire();

    final state =
        await client.connection.attempt(budget: const Duration(seconds: 5));

    expect(state.isOnline, isTrue, reason: '$state');
    expect(client.getRemoteSecondary()!.attemptsOpen, 0);
  });

  test('an attempt that fails with a local fault closes its watch', () async {
    edge.pkamFault = AtSigningException('the signing key is unreadable');
    final client = await clientOverWire();

    await expectLater(
        () => client.connection.attempt(budget: const Duration(seconds: 5)),
        throwsA(isA<AtSigningException>()));

    expect(client.getRemoteSecondary()!.attemptsOpen, 0);
  });

  test(
      'a budget that ends after the challenge does not hide a local fault as '
      'offline', () async {
    // The challenge arrives at once; the fault that follows is the client's
    // own, and it lands after the budget.
    final fault = AtSigningException('the signing key is unreadable');
    edge
      ..pkamDelay = const Duration(milliseconds: 300)
      ..pkamFault = fault;
    final client = await clientOverWire();

    await expectLater(
        () => client.connection
            .attempt(budget: const Duration(milliseconds: 100)),
        throwsA(same(fault)),
        reason: 'a local fault is not a statement about the atServer, so it '
            'is thrown as itself however late it arrives');

    expect(
        client.connection.current.cause, isNot(AtConnectionCause.unreachable),
        reason: '${client.connection.current}: the atServer was reached, so '
            'no offline state may be recorded for a local fault');
  });

  test(
      'a budget that ends after the challenge reports the atServer\'s refusal '
      'as itself, not offline', () async {
    // The challenge arrives at once; the atServer then refuses the
    // authentication, and the refusal lands after the budget.
    edge
      ..pkamDelay = const Duration(milliseconds: 300)
      ..pkamFault = UnAuthenticatedException('AT0401-pkam signature rejected');
    final client = await clientOverWire();

    final state = await client.connection
        .attempt(budget: const Duration(milliseconds: 100));

    expect(state.cause, isNot(AtConnectionCause.unreachable),
        reason: '$state: the atServer answered, so a refusal that lands after '
            'the budget is a statement about the credentials, not offline');
  });

  test(
      'a verb that starts another run mid-attempt does not turn an answered '
      'challenge into offline', () async {
    // The attempt's challenge is answered at once and its pkam: reply lands
    // after the budget. Between the two, a verb starts an authenticator run
    // of its own whose from: the atServer has not answered.
    edge.pkamDelay = const Duration(milliseconds: 300);
    final client = await clientOverWire();
    final remote = client.getRemoteSecondary()!;

    final attempt =
        client.connection.attempt(budget: const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final held = Completer<String>();
    edge.holds.add(held);
    final verbRun = remote.atLookUp.authenticator!(_EdgeExecutor(edge));
    unawaited(verbRun.then((_) {}, onError: (_) {}));

    final state = await attempt;
    held.complete(challengeNamed(atSign));

    expect(state.isOnline, isTrue,
        reason: '$state: the attempt\'s own challenge was answered, so a run '
            'the verb started cannot make the budget read as an unreachable '
            'atServer');
  });

  test(
      'an attempt hears every run started while it waits, whichever run the '
      'atServer answers first', () async {
    // A verb's run claims the slot the attempt's own run would have: the
    // first run is never answered, the second is, and the attempt is
    // answered all the same - it is the atServer that answered, not a run.
    final client = await clientOverWire();
    final remote = client.getRemoteSecondary()!;
    final held = Completer<String>();
    edge.holds.add(held);

    final attempt = remote.beginAttempt();
    final verbRun = remote.atLookUp.authenticator!(_EdgeExecutor(edge));
    unawaited(verbRun.then((_) {}, onError: (_) {}));
    final ownRun = remote.atLookUp.authenticator!(_EdgeExecutor(edge));
    unawaited(ownRun.then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(attempt.answered, isTrue,
        reason: 'the second run was answered while the attempt waited');
    held.complete(challengeNamed(atSign));
  });

  test('an attempt that has ended is not answered by a later run', () async {
    final client = await clientOverWire();
    final remote = client.getRemoteSecondary()!;

    final attempt = remote.beginAttempt()..end();
    final run = remote.atLookUp.authenticator!(_EdgeExecutor(edge));
    unawaited(run.then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(attempt.answered, isFalse,
        reason: 'the attempt had finished before this run started');
  });

  test('an attempt is unanswered until the atServer answers a run', () async {
    final client = await clientOverWire();
    final remote = client.getRemoteSecondary()!;
    final held = Completer<String>();
    edge.holds.add(held);

    final attempt = remote.beginAttempt();
    expect(attempt.answered, isFalse, reason: 'no run has started');
    final run = remote.atLookUp.authenticator!(_EdgeExecutor(edge));
    unawaited(run.then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(attempt.answered, isFalse, reason: 'the run has not been answered');

    held.complete(challengeNamed(atSign));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(attempt.answered, isTrue,
        reason: 'the atServer answered the run\'s from: with a challenge');
  });

  test('a late challenge from an earlier run does not answer a later run',
      () async {
    // Neither run is answered while it is being waited on: the first gives up
    // on its budget with its `from:` still in flight, and the second is still
    // waiting when the first run's challenge finally lands.
    final earlier = Completer<String>();
    final later = Completer<String>();
    edge.holds.addAll([earlier, later]);
    final client = await clientOverWire();

    final first = await client.connection
        .attempt(budget: const Duration(milliseconds: 100));
    expect(first.isOffline, isTrue, reason: '$first');
    expect(first.cause, AtConnectionCause.unreachable,
        reason: 'the first run heard nothing before its budget');

    // A later attempt starts a run of its own, which the connection waits on
    // and which the earlier challenge's flag no longer stands for.
    final second =
        client.connection.attempt(budget: const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(wire.pkams, 2, reason: 'the second attempt started its own run');

    // The first run's challenge arrives now, on a run nobody waits on.
    earlier.complete(challengeNamed(atSign));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = await second;
    expect(state.isOffline, isTrue, reason: '$state');
    expect(state.cause, AtConnectionCause.unreachable,
        reason: 'the second run heard nothing of its own, so its budget '
            'alone answers for it');

    // Release the second run so nothing outlives the test.
    later.complete(challengeNamed(atSign));
    await Future<void>.delayed(Duration.zero);
  });

  test('a late challenge from an earlier run does not answer a later attempt',
      () async {
    final client = await clientOverWire();
    final remote = client.getRemoteSecondary()!;
    final earlier = Completer<String>();
    final later = Completer<String>();
    edge.holds.addAll([earlier, later]);

    final first = remote.beginAttempt();
    final firstRun = remote.atLookUp.authenticator!(_EdgeExecutor(edge));
    unawaited(firstRun.then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    first.end();

    final second = remote.beginAttempt();
    final secondRun = remote.atLookUp.authenticator!(_EdgeExecutor(edge));
    unawaited(secondRun.then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    earlier.complete(challengeNamed(atSign));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second.answered, isFalse,
        reason: 'the reply answers a run that started before this attempt');

    later.complete(challengeNamed(atSign));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second.answered, isTrue);
    second.end();
  });

  test(
      'a budget that ends after the challenge still reports offline when the '
      'lookup itself times out', () async {
    // The challenge arrives at once, so the budget is not what ends the
    // attempt: the lookup's own read of the `pkam:` reply times out after it.
    // The residual this pins is that such a timeout is still read as an
    // unreachable atServer, whatever the challenge; changing it is a decision
    // to make deliberately.
    edge
      ..pkamDelay = const Duration(milliseconds: 300)
      ..pkamFault = TimeoutException('the lookup stopped awaiting pkam:');
    final client = await clientOverWire();

    final state = await client.connection
        .attempt(budget: const Duration(milliseconds: 100));

    expect(state.isOffline, isTrue, reason: '$state');
    expect(state.cause, AtConnectionCause.unreachable,
        reason: 'a timeout the lookup raises from its own read is reported '
            'offline, whatever the challenge');
  });
}

/// The `from:` answer [atSign]'s atServer gives: a challenge issued to it.
String challengeNamed(String atSign) =>
    'data:_123e4567-e89b-12d3-a456-426614174000$atSign:'
    '123e4567-e89b-12d3-a456-426614174000';

/// What the test times on the wire: held `from:` answers, and a `pkam:`
/// answer that lands late, or throws instead.
class _Edge {
  _Edge(this.wire);

  final Wire wire;

  /// One entry per authenticator run whose `from:` the test holds: each run's
  /// `from:` takes the next one when any remain and waits on it until the
  /// test completes it, so the test owns each run's leg separately.
  final List<Completer<String>> holds = [];

  /// How long the `pkam:` reply takes to land.
  Duration pkamDelay = Duration.zero;

  /// When set, the `pkam:` reply handler throws this instead of answering.
  Object? pkamFault;
}

/// [Wire]'s factory, building a lookUp that runs the authenticator through
/// [_EdgeExecutor] so the test owns the timing of each leg.
AtLookUpFactory _lookUpsOver(Wire wire, _Edge edge) => ({
      required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder,
    }) {
      wire.dials++;
      wire.finders.add(secondaryAddressFinder);
      final lookUp = _EdgeLookUp(wire, edge)..authenticator = authenticator;
      wire.lookUpsBuilt.add(lookUp);
      return lookUp;
    };

/// [WireLookUp] with the timing the [Wire] fakes have no knob for: the
/// authenticator runs exactly as at_lookup runs it, against an executor whose
/// `from:` and `pkam:` answers the test schedules.
class _EdgeLookUp extends WireLookUp {
  _EdgeLookUp(this._wire, this._edge) : super(_wire);

  final Wire _wire;
  final _Edge _edge;

  @override
  Future<bool> pkamAuthenticate() async {
    _wire.pkams++;
    if (_wire.connectFails) {
      throw SecondaryConnectException('connection refused');
    }
    // The real lookup connects and takes its mutex before it starts the
    // authenticator, so the run does not exist yet when this call returns.
    await Future<void>.delayed(Duration.zero);
    final run = authenticator;
    if (_wire.runsAuthenticator && run != null) {
      return run(_EdgeExecutor(_edge));
    }
    if (_wire.pkamScript.isNotEmpty) {
      return _wire.pkamScript.removeFirst().future;
    }
    return _wire.pkamAccepted;
  }
}

/// The connection the authenticator sees: `from:` answers with a challenge
/// naming the atSign asked for — or waits on the next of [Edge.holds] — and
/// `pkam:` is answered after [Edge.pkamDelay], or throws [Edge.pkamFault].
class _EdgeExecutor implements AtCommandExecutor {
  _EdgeExecutor(this._edge);

  final _Edge _edge;

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    if (command.startsWith('from:')) {
      if (_edge.holds.isNotEmpty) return _edge.holds.removeAt(0).future;
      final atSign = command.substring(5).split(RegExp('[:\\n]')).first.trim();
      final named = atSign.startsWith('@') ? atSign : '@$atSign';
      return challengeNamed(named);
    }
    if (command.startsWith('pkam:')) {
      _edge.wire.pkamCommands.add(command);
      if (_edge.pkamDelay > Duration.zero) {
        await Future<void>.delayed(_edge.pkamDelay);
      }
      final fault = _edge.pkamFault;
      if (fault != null) throw fault;
      return _edge.wire.pkamReply;
    }
    return 'error:unexpected $command';
  }
}
