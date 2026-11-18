import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:at_demo_data/at_demo_data.dart' show cramKeyMap;
import 'package:at_lookup/at_lookup_io.dart';
import 'package:test/test.dart';

import 'utils/passkey_rig.dart';

/// Passkey custody against the virtualenv. Every test takes an atSign of its
/// own that no other test in this pack activates, because a CRAM secret
/// serves one activation per virtualenv.
void main() {
  setUpAll(() async {
    expect(await _cramLogin('@cloudvm2'), 'accepted',
        reason: 'the CRAM probe accepts a secret the atServer still holds');
  });

  test('Onboarding returns a client that is online as the new enrollment',
      () async {
    const atSign = '@barbara';
    final rig = PasskeyRig(salt: 11);

    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId,
        await rig.pointedEnrollmentId(atSign, rig.currentPrf),
        reason: 'the client runs as the enrollment the pointer names');
  }, timeout: _timeout);

  test(
      'Logging in on a device that remembers nothing returns a client '
      'online as the pointed enrollment', () async {
    const atSign = '@chris';
    final rig = PasskeyRig(salt: 12);
    await (await _onboard(rig, atSign)).stop();

    final session =
        await rig.custody(hints: MemoryHints()).open(atSign: atSign);
    addTearDown(session.stop);

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId,
        await rig.pointedEnrollmentId(atSign, rig.currentPrf));
  }, timeout: _timeout);

  test('A @keys document a passkey client writes holds no APKAM private key',
      () async {
    const atSign = '@cloudvm1';
    final rig = PasskeyRig(salt: 13);
    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);
    final enrollmentId = session.client.enrollmentId!;

    await _file(session.client, atSign, 'f0readback', 'readback');

    final held = jsonEncode(
        (await (session.client.atKeysIo! as WrittenAtKeysIo).read(atSign))
            .toJson());
    expect(held, contains('"privateAuthentication"'),
        reason: "the check finds the key in keys that hold it: the client's");
    final stored = jsonEncode(
        await rig.storedDocument(atSign, enrollmentId, rig.currentPrf));
    expect(stored, contains(_b('readback-priv')),
        reason: 'the document holds the new material');
    expect(stored, isNot(contains('"$apkamPrivateKey"')),
        reason: 'no flat APKAM private key is stored');
    expect(stored, isNot(contains('"privateAuthentication"')),
        reason: 'no typed APKAM private key is stored');
  }, timeout: _timeout);

  test(
      'Two clients of one enrollment add key material at once, and both '
      'additions survive', () async {
    const atSign = '@colin';
    final rig = PasskeyRig(salt: 21);
    final onboarded = await _onboard(rig, atSign);
    final enrollmentId = onboarded.client.enrollmentId!;
    final prf = Uint8List.fromList(rig.currentPrf);
    final credential = rig.port.current!;
    await onboarded.stop();

    final results = ReceivePort();
    final replies = StreamIterator(results);
    for (final tag in ['one', 'two']) {
      await Isolate.spawn(
          _isolateWriter, [results.sendPort, atSign, credential, prf, tag]);
    }
    final goes = <SendPort>[];
    for (var i = 0; i < 2; i++) {
      expect(await replies.moveNext(), isTrue);
      final ready = replies.current as List;
      expect(ready.first, 'ready', reason: '${ready.last}');
      goes.add(ready.last as SendPort);
    }
    await Future<void>.delayed(_pastTheLock);
    for (final go in goes) {
      go.send('go');
    }
    final done = <List>[];
    for (var i = 0; i < 2; i++) {
      expect(await replies.moveNext(), isTrue);
      done.add(replies.current as List);
    }
    results.close();
    for (final d in done) {
      print('LIVE writer ${d[1]}: ${d[0]} after ${d[2]} ms, '
          '${d[3]} lock takes refused');
    }

    expect(done.map((d) => d[0]), everyElement('ok'));
    expect(
        done.map((d) => d[3] as int).fold(0, (a, b) => a + b), greaterThan(0),
        reason: 'one writer found the lock the other held');
    final stored =
        jsonEncode(await rig.storedDocument(atSign, enrollmentId, prf));
    expect(stored, contains(_b('one-priv')));
    expect(stored, contains(_b('two-priv')));
  }, timeout: _timeout);

  test(
      "A write that finds the lock held waits, re-reads and keeps the other "
      "writer's change", () async {
    const atSign = '@device1';
    final rig = PasskeyRig(salt: 22);
    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);
    final enrollmentId = session.client.enrollmentId!;
    final prf = Uint8List.fromList(rig.currentPrf);
    await Future<void>.delayed(_pastTheLock);

    final other = await _otherWriter(rig, atSign, enrollmentId, prf);
    addTearDown(other.close);
    await other.store.update(atSign.toAtsign(), (keys) {
      _fileOn(keys, 'f0otherwriter', 'other');
      return true;
    });
    final otherPut =
        rig.tap.lines.lastIndexWhere((l) => l.sent && _isDocumentPut(l.text));
    final mark = rig.tap.lines.length;

    await _file(session.client, atSign, 'f0client', 'client');

    final refused = _refusedTakes(rig.tap, from: mark);
    print('LIVE lock takes refused before the client took it: $refused');
    expect(refused, greaterThan(0), reason: 'the client found it held');
    final put = rig.tap.indexOfSent(_isDocumentPut, from: mark);
    expect(put, greaterThan(otherPut));
    expect(
        rig.tap.indexOfSent((c) => c.startsWith('llookup:atkeys.'), from: mark),
        lessThan(put),
        reason: 'it re-read the document before it put');
    final stored =
        jsonEncode(await rig.storedDocument(atSign, enrollmentId, prf));
    expect(stored, contains(_b('other-priv')),
        reason: "it kept the other writer's change");
    expect(stored, contains(_b('client-priv')));
  }, timeout: _timeout);

  test("Every @keys write holds the enrollment's lock", () async {
    const atSign = '@don';
    final rig = PasskeyRig(salt: 23);
    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);
    await Future<void>.delayed(_pastTheLock);

    await _file(session.client, atSign, 'f0every1', 'every1');
    await _file(session.client, atSign, 'f0every2', 'every2');

    final lines = rig.tap.lines;
    final puts = [
      for (var i = 0; i < lines.length; i++)
        if (_isDocumentPut(lines[i].text) && lines[i].sent) i
    ];
    print('LIVE document puts: ${puts.length}');
    expect(puts.length, greaterThanOrEqualTo(3));
    for (final put in puts) {
      final takes = [
        for (var i = 0; i < put; i++)
          if (lines[i].sent &&
              lines[i].text.contains('atkeys-lock.') &&
              _accepted(rig.tap, i) &&
              lines[put].at.difference(lines[i].at) < _lockTtl)
            i
      ];
      expect(takes, isNotEmpty,
          reason: 'put #$put was sent within the ttl of a lock this '
              'process took:\n${rig.tap.transcript()}');
    }
  }, timeout: _timeout);

  test(
      'Onboarding writes the @keys document and pointer before it deletes '
      'the CRAM secret', () async {
    const atSign = '@gareth';
    final rig = PasskeyRig(salt: 31);
    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);
    final enrollmentId = session.client.enrollmentId!;

    final tap = rig.tap;
    final delete = tap.indexOfSent(_isCramDelete);
    final document = _replyIndex(tap, tap.indexOfSent(_isDocumentPut));
    final pointer = _replyIndex(tap, tap.indexOfSent(_isPointerPut));
    expect(delete, greaterThan(-1));
    expect(_accepted(tap, tap.indexOfSent(_isDocumentPut)), isTrue);
    expect(_accepted(tap, tap.indexOfSent(_isPointerPut)), isTrue);
    expect(document, lessThan(delete),
        reason: 'the document was stored before the delete was sent');
    expect(pointer, lessThan(delete),
        reason: 'the pointer was stored before the delete was sent');
    final stored =
        await rig.storedDocument(atSign, enrollmentId, rig.currentPrf);
    expect(stored['aesEncryptPublicKey'], isA<String>());
    final cram = await _cramLogin(atSign);
    print('LIVE cram: after onboarding: $cram');
    expect(cram, startsWith('refused'));
  }, timeout: _timeout);

  test('A signing root is published only after the CRAM secret is deleted',
      () async {
    const atSign = '@xavier';
    final rig = _PqReadyRig();
    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);
    await (session.client as AtClientImpl)
        .pqBootstrap!
        .startupComplete
        .timeout(const Duration(seconds: 90));

    final tap = rig.tap;
    final delete = tap.indexOfSent(_isCramDelete);
    final root = tap.indexOfSent(_isRootPublish);
    expect(delete, greaterThan(-1));
    expect(root, greaterThan(-1), reason: tap.transcript());
    expect(root, greaterThan(delete),
        reason: 'the root was first published after the CRAM secret was '
            'deleted');
    final lastPut = tap.lines
        .sublist(0, root)
        .lastIndexWhere((l) => l.sent && _isDocumentPut(l.text));
    expect(_accepted(tap, lastPut), isTrue);
    final sealed = tap.lines[lastPut].text
        .substring(tap.lines[lastPut].text.indexOf(' ') + 1);
    final keys = await deriveFor(rig.currentPrf, atSign);
    final Map<String, dynamic> heldBefore;
    try {
      heldBefore = await keys.vault.open(PasskeyRecordType.atkeys, sealed);
    } finally {
      keys.vault.close();
    }
    final published = jsonDecode(tap.lines[root].text
        .substring(tap.lines[root].text.indexOf(' ') + 1)) as Map;
    final rootPub = ((published['keys'] as List).single as Map)['pub'];
    final atSignKeys = jsonEncode(heldBefore['atsignKeys']);
    print('LIVE root kid ${((published['keys'] as List).single as Map)['kid']}'
        ' in the document before it was published: '
        '${atSignKeys.contains('"privateSigning"')}');
    expect(atSignKeys, contains('"privateSigning"'),
        reason: "the document held the root's private key first");
    expect(atSignKeys, contains('$rootPub'),
        reason: 'the key it held is the one published');
  }, timeout: _timeout);

  group(
      'An onboarding interrupted before the CRAM secret is deleted can be '
      'run again with the same secret', () {
    final interruptions = <String, (String, bool Function(String))>{
      'after its enrollment was approved': (
        '@gateway2',
        (c) => c.contains('atkeys-lock.')
      ),
      'after its @keys document was written': ('@jeremy', _isPointerPut),
      'after its pointer was written': (
        '@policy1',
        (c) => c.startsWith('enroll:list')
      ),
      'after its encryption public key was published': (
        '@policy2',
        _isCramDelete
      ),
    };
    for (final MapEntry(key: point, value: (atSign, cut))
        in interruptions.entries) {
      test(
          'An onboarding interrupted before the CRAM secret is deleted can '
          'be run again with the same secret: $point', () async {
        final rig = PasskeyRig(salt: 40 + point.length);
        await _interrupted(rig, atSign, cut);

        final session = await _onboard(rig, atSign);
        addTearDown(session.stop);

        expect(session.client.connection.current.isOnline, isTrue);
        expect(rig.port.credentials, hasLength(2), reason: 'a new passkey');
      }, timeout: _timeout);
    }
  });

  test('The retry revokes the enrollments interrupted attempts left approved',
      () async {
    const atSign = '@relay1';
    final rig = PasskeyRig(salt: 51);
    await _interrupted(rig, atSign, (c) => c.contains('atkeys-lock.'));
    final earlier = _requestedEnrollmentId(rig.tap)!;
    final mark = rig.tap.lines.length;

    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);

    final tap = rig.tap;
    final revoke = tap.indexOfSent(
        (c) => c.startsWith('enroll:revoke') && c.contains(earlier),
        from: mark);
    final delete = tap.indexOfSent(_isCramDelete, from: mark);
    expect(revoke, greaterThan(-1), reason: tap.transcript());
    expect(_accepted(tap, revoke), isTrue);
    expect(_replyIndex(tap, revoke), lessThan(delete),
        reason: 'the earlier enrollment was revoked before the delete');
    expect(
        await _approved(session.client, atSign), {session.client.enrollmentId});
  }, timeout: _timeout);

  test(
      "The retry publishes its own encryption public key over an "
      "interrupted attempt's", () async {
    const atSign = '@relay2';
    final rig = PasskeyRig(salt: 52);
    await _interrupted(rig, atSign, _isCramDelete);
    final first = _publishedKey(rig.tap, from: 0);
    expect(first, isNotNull, reason: 'the first attempt published its key');

    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);

    final own = (await rig.storedDocument(atSign, session.client.enrollmentId!,
        rig.currentPrf))['aesEncryptPublicKey'];
    expect(await publicLookupReply(atSign, 'publickey'), 'data:$own');
    expect(own, isNot(first));
  }, timeout: _timeout);

  test('A passkey left by an interrupted onboarding is refused as lost',
      () async {
    const atSign = '@gateway1';
    final rig = PasskeyRig(salt: 53);
    await _interrupted(rig, atSign, (c) => c.startsWith('enroll:list'));
    await (await _onboard(rig, atSign)).stop();

    rig.port.current = 1;
    await expectLater(
        rig.custody(hints: MemoryHints()).open(atSign: atSign),
        throwsA(isA<PasskeyLostException>()
            .having((e) => e.reason, 'reason', 'PKAM refused')),
        reason: "the first passkey's enrollment was revoked");
  }, timeout: _timeout);

  test(
      'An onboarding interrupted after the CRAM secret is deleted is '
      'finished by logging in', () async {
    const atSign = '@gary';
    final rig = PasskeyRig(salt: 54);
    await _interrupted(
        rig, atSign, (_) => rig.tap.indexOfSent(_isCramDelete) >= 0);
    final onboarded = _requestedEnrollmentId(rig.tap);

    final session =
        await rig.custody(hints: MemoryHints()).open(atSign: atSign);
    addTearDown(session.stop);

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, onboarded);
  }, timeout: _timeout);

  test(
      'A login after an onboarding that stopped before deleting the CRAM '
      'secret deletes it', () async {
    const atSign = '@sachin';
    final rig = PasskeyRig(salt: 55);
    await _interrupted(rig, atSign, _isCramDelete);
    expect(await _cramLogin(atSign), 'accepted',
        reason: 'the onboarding left the CRAM secret');
    final mark = rig.tap.lines.length;

    final session =
        await rig.custody(hints: MemoryHints()).open(atSign: atSign);
    addTearDown(session.stop);

    final cram = await _cramLogin(atSign);
    print('LIVE cram: after the login: $cram');
    expect(cram, startsWith('refused'),
        reason: 'the login deleted the CRAM secret');
    expect(_accepted(rig.tap, rig.tap.indexOfSent(_isCramDelete, from: mark)),
        isTrue,
        reason: 'the login sent the delete');
  }, timeout: _timeout);

  test(
      'A login after an onboarding that stopped before publishing its '
      'encryption public key publishes it and deletes the CRAM secret',
      () async {
    const atSign = '@device2';
    final rig = PasskeyRig(salt: 56);
    await _interrupted(rig, atSign, (c) => _publishes(c, atSign));
    expect(await publicLookupReply(atSign, 'publickey'), contains('AT0015'),
        reason: 'the onboarding published no encryption public key');

    final session =
        await rig.custody(hints: MemoryHints()).open(atSign: atSign);
    addTearDown(session.stop);

    final own = (await rig.storedDocument(atSign, session.client.enrollmentId!,
        rig.currentPrf))['aesEncryptPublicKey'];
    expect(await publicLookupReply(atSign, 'publickey'), 'data:$own');
    final cram = await _cramLogin(atSign);
    print('LIVE cram: after the login: $cram');
    expect(cram, startsWith('refused'));
  }, timeout: _timeout);
}

const _timeout = Timeout(Duration(minutes: 3));

/// The ttl each take of the @keys lock lasts.
const _lockTtl = Duration(seconds: 10);

/// Long enough for a lock taken before it to have expired.
const _pastTheLock = Duration(seconds: 11);

String _b(String s) => base64Encode(utf8.encode(s));

Future<PasskeySession> _onboard(PasskeyRig rig, String atSign) =>
    rig.custody().onboard(atSign: atSign, cram: cramKeyMap[atSign]!);

/// Runs an onboarding of [atSign] whose network is cut at the first command
/// [cut] matches, and then restored.
Future<void> _interrupted(
    PasskeyRig rig, String atSign, bool Function(String) cut) async {
  rig.tap.dropOn = cut;
  await expectLater(_onboard(rig, atSign), throwsA(anything));
  expect(rig.tap.dropped, isNotEmpty, reason: 'the network was cut');
  print('LIVE cut at: ${rig.tap.dropped.first.split(' ').first}');
  rig.tap.severed = false;
}

bool _isDocumentPut(String c) => c.startsWith('update:atkeys.');

bool _isPointerPut(String c) => c.startsWith('update:public:_');

bool _isCramDelete(String c) => c.startsWith('delete:privatekey:at_secret');

bool _isRootPublish(String c) =>
    c.startsWith('update:') && c.contains('public:pq_signing_root@');

bool _publishes(String c, String atSign) =>
    c.startsWith('update:') && c.contains('public:publickey$atSign ');

/// The value the first `publickey` publish sent at or after [from] carried.
String? _publishedKey(WireTap tap, {required int from}) {
  for (final l in tap.lines.skip(from)) {
    if (l.sent &&
        l.text.startsWith('update:') &&
        l.text.contains('public:publickey@')) {
      return l.text.substring(l.text.indexOf(' ') + 1);
    }
  }
  return null;
}

/// The index of the reply to the command at [sent], or -1.
int _replyIndex(WireTap tap, int sent) {
  if (sent < 0) return -1;
  final connection = tap.lines[sent].connection;
  for (var i = sent + 1; i < tap.lines.length; i++) {
    final l = tap.lines[i];
    if (!l.sent && l.connection == connection && l.text.contains(':')) {
      return i;
    }
  }
  return -1;
}

/// Whether the command at [sent] was answered with data.
bool _accepted(WireTap tap, int sent) {
  final reply = _replyIndex(tap, sent);
  return reply >= 0 &&
      tap.lines[reply].text.contains('data:') &&
      !tap.lines[reply].text.contains('error:');
}

/// How many takes of the @keys lock sent at or after [from] were refused.
int _refusedTakes(WireTap tap, {required int from}) {
  var refused = 0;
  for (var i = from; i < tap.lines.length; i++) {
    final l = tap.lines[i];
    if (l.sent && l.text.contains('atkeys-lock.') && !_accepted(tap, i)) {
      refused++;
    }
  }
  return refused;
}

/// The enrollment id the atServer gave the first `enroll:request`.
String? _requestedEnrollmentId(WireTap tap) {
  final reply =
      _replyIndex(tap, tap.indexOfSent((c) => c.startsWith('enroll:request')));
  if (reply < 0) return null;
  return RegExp(r'"enrollmentId":"([^"]+)"')
      .firstMatch(tap.lines[reply].text)
      ?.group(1);
}

/// The ids of [atSign]'s approved enrollments, as [client] lists them.
Future<Set<String>> _approved(AtClient client, String atSign) async {
  final reply = await client.getRemoteSecondary()!.executeCommand(
      'enroll:list:{"enrollmentStatusFilter":["approved"]}\n',
      auth: true);
  final listed =
      jsonDecode(reply!.substring(reply.indexOf('data:') + 5)) as Map;
  return {for (final key in listed.keys) (key as String).split('.').first};
}

/// `accepted` when a `cram:` login of [atSign] with its CRAM secret succeeds
/// on a connection of its own, else `refused:` and the reason.
Future<String> _cramLogin(String atSign) async {
  final lookUp = secureSocketLookUps()(
      atSign: atSign, rootDomain: veRoot, authenticator: null);
  try {
    lookUp.authenticator =
        authenticatorForCramSecret(atSign, cramKeyMap[atSign]!);
    return await lookUp.pkamAuthenticate() ? 'accepted' : 'refused: false';
  } on Exception catch (e) {
    return 'refused: $e';
  } finally {
    await lookUp.close();
  }
}

/// Files signing material for a stand-in enrollment [enrollmentId], tagged
/// [tag], in [keys].
void _fileOn(AtKeys keys, String enrollmentId, String tag) =>
    keys.fileSigningMaterial(
        enrollmentId: enrollmentId,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        publicKey: _b('$tag-pub'),
        privateKey: _b('$tag-priv'));

/// Files material tagged [tag] through [client]'s @keys store.
Future<void> _file(
        AtClient client, String atSign, String enrollmentId, String tag) =>
    (client.atKeysIo! as WrittenAtKeysIo).update(atSign.toAtsign(), (keys) {
      _fileOn(keys, enrollmentId, tag);
      return true;
    });

/// A second writer of [enrollmentId]'s document: a connection of its own
/// and a store over it, as another device of the enrollment holds.
Future<({AtServerAtKeysIo store, Future<void> Function() close})> _otherWriter(
    PasskeyRig rig, String atSign, String enrollmentId, Uint8List prf) async {
  final keys = await deriveFor(prf, atSign);
  final pair = await apkamKeyPairFromSeed(keys.authSeed);
  final session = await rig.gateway().authenticate(
      atSign: atSign, enrollmentId: enrollmentId, apkamKeyPair: pair);
  final store = AtServerAtKeysIo(
      documents: session.documents,
      atSign: atSign,
      seal: (d) => keys.vault.seal(PasskeyRecordType.atkeys, d),
      open: (r) => keys.vault.open(PasskeyRecordType.atkeys, r),
      enrollmentId: enrollmentId,
      apkamKeyPair: pair);
  return (
    store: store,
    close: () async {
      store.close();
      await session.close();
      keys.vault.close();
    }
  );
}

/// One client of the enrollment, in an isolate of its own: logs in with the
/// passkey it is given, says it is ready, files material tagged with its
/// name when told to go, and reports how the write went.
Future<void> _isolateWriter(List<Object> args) async {
  final results = args[0] as SendPort;
  final atSign = args[1] as String;
  final credential = args[2] as int;
  final prf = args[3] as Uint8List;
  final tag = args[4] as String;
  final rig = PasskeyRig(
      port: VePasskeyPort.holding(Uint8List.fromList([credential]), prf));
  final PasskeySession session;
  try {
    session = await rig.custody(hints: MemoryHints()).open(atSign: atSign);
    await (session.client as AtClientImpl).pqBootstrap?.startupComplete;
  } on Object catch (e) {
    results.send(['failed', '$tag: $e']);
    return;
  }
  final go = ReceivePort();
  results.send(['ready', go.sendPort]);
  await go.first;
  final mark = rig.tap.lines.length;
  final clock = Stopwatch()..start();
  var outcome = 'ok';
  try {
    await _file(session.client, atSign, 'f0$tag', tag);
  } on Object catch (e) {
    outcome = '$e';
  }
  results.send([
    outcome,
    tag,
    clock.elapsedMilliseconds,
    _refusedTakes(rig.tap, from: mark)
  ]);
  await session.stop();
}

/// A rig whose client runs under a posture that creates a signing root.
class _PqReadyRig extends PasskeyRig {
  _PqReadyRig() : super(salt: 93);

  @override
  Future<AtClient> openClient(
      {required AtLookupMuxable lookUp,
      required String atSign,
      required String enrollmentId,
      required WrittenAtKeysIo keysIo}) async {
    final client = await Atsign(atSign).open(
        keys: keysIo,
        preference: AtClientPreference(posture: PqPosture.pqReady)
          ..namespace = 'wavi'
          ..rootDomain = veRoot.rootDomain
          ..rootPort = veRoot.rootPort
          ..remoteLocalPref = RemoteLocalPref.remoteOnly
          ..monitorAutoStart = false,
        namespace: 'wavi',
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
        atLookUp: lookUp,
        lookUps: lookUps,
        secondaryAddressFinder: finder);
    if (!client.connection.current.isOnline) {
      await client.stop();
      throw StateError('the client of $atSign opened offline');
    }
    return client;
  }
}
