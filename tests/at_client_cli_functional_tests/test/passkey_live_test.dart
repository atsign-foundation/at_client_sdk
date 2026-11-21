import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/passkey.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/lifecycle/authenticated_lookup.dart';
import 'package:at_client/src/lifecycle/pending_enrollment.dart'
    show handshakeKeysIo;
import 'package:at_client/src/passkey/completion_due_record.dart'
    show CompletionDueRecord;
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed, withApkamKey;
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
    final writers = <Isolate>[];
    // On any path out of the test, the writers are killed, which closes the
    // sessions they hold, and the port is closed.
    addTearDown(() {
      for (final writer in writers) {
        writer.kill(priority: Isolate.immediate);
      }
      results.close();
    });
    for (final tag in ['one', 'two']) {
      // An error the writer does not catch arrives as a reply that is not
      // 'ready', so the test fails rather than waits for it.
      writers.add(await Isolate.spawn(
          _isolateWriter, [results.sendPort, atSign, credential, prf, tag],
          onError: results.sendPort));
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
    expect(done.map((d) => d[0]), everyElement('ok'),
        reason: 'each writer reports how its write went, not an error');
    for (final d in done) {
      print('LIVE writer ${d[1]}: ${d[0]} after ${d[2]} ms, '
          '${d[3]} lock takes refused');
    }

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

    // The other writer holds the lock and its put until the client has found
    // the lock held, so a client that read before it took the lock would
    // have read a document without the other writer's change.
    final putReached = Completer<void>();
    final releasePut = Completer<void>();
    final other = await _otherWriter(rig, atSign, enrollmentId, prf,
        wrap: (documents) =>
            _HeldPut(documents, reached: putReached, release: releasePut));
    addTearDown(other.close);
    final otherWrite = other.store.update(atSign.toAtsign(), (keys) {
      _fileOn(keys, 'f0otherwriter', 'other');
      return true;
    });
    await Future.any([putReached.future, otherWrite]);
    expect(putReached.isCompleted, isTrue,
        reason: 'the control: the other writer reached its put');
    final mark = rig.tap.lines.length;
    rig.tap.onLine = () {
      if (!releasePut.isCompleted && _answeredRefusals(rig.tap, mark) > 0) {
        releasePut.complete();
      }
    };
    addTearDown(() => rig.tap.onLine = null);

    await Future.wait(
        [otherWrite, _file(session.client, atSign, 'f0client', 'client')],
        eagerError: true);
    expect(releasePut.isCompleted, isTrue,
        reason: 'the other put waited until the client found the lock held');

    final refused = _refusedTakes(rig.tap, from: mark);
    print('LIVE lock takes refused before the client took it: $refused');
    expect(refused, greaterThan(0), reason: 'the client found it held');
    final tap = rig.tap;
    final refusedTake = _refusedTakeAfter(tap, mark);
    expect(refusedTake, greaterThan(-1),
        reason: 'the client was refused a take of the lock');
    final client = tap.lines[refusedTake].connection;
    final otherPut = _indexOn(tap, (c) => c != client, _isDocumentPut, mark);
    expect(otherPut, greaterThan(-1),
        reason: "the control: the other writer's put went on a connection of "
            'its own');
    final put = _indexOn(tap, (c) => c == client, _isDocumentPut, mark);
    final took =
        _indexOn(tap, (c) => c == client, _isLockTake, mark, accepted: true);
    print('LIVE client connection $client took the lock at $took and put at '
        '$put; the other writer put at $otherPut');
    expect(put, greaterThan(-1), reason: 'the client put the document');
    expect(took, allOf(greaterThan(-1), lessThan(put)),
        reason: 'it took the lock before it put');
    final reread = _indexOn(
        tap, (c) => c == client, (t) => t.startsWith('llookup:atkeys.'), took);
    expect(reread, allOf(greaterThan(took), lessThan(put)),
        reason: 'it re-read the document once it held the lock, before it '
            'put');
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
    // The first write's lease now has less than half its ttl left, so the
    // second write cannot put on it.
    await Future<void>.delayed(_pastHalfTheLock);
    await _file(session.client, atSign, 'f0every2', 'every2');

    final lines = rig.tap.lines;
    final puts = [
      for (var i = 0; i < lines.length; i++)
        if (_isDocumentPut(lines[i].text) && lines[i].sent) i
    ];
    print('LIVE document puts: ${puts.length}');
    expect(puts.length, greaterThanOrEqualTo(3));
    for (final put in puts) {
      final took = _acceptedTakeBefore(rig.tap, put);
      expect(took, greaterThan(-1),
          reason: 'put #$put follows a lock this process took:\n'
              '${rig.tap.transcript()}');
      expect(lines[put].at.difference(lines[took].at),
          lessThanOrEqualTo(_lockTtl ~/ 2 + _tapSlack),
          reason: 'put #$put was sent with at least half the ttl of the '
              'lock it holds left:\n${rig.tap.transcript()}');
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

  test(
      'Onboarding deletes the CRAM secret, then revokes the other '
      'enrollments, then publishes its encryption public key', () async {
    const atSign = '@policy2';
    final rig = PasskeyRig(salt: 32);
    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);

    final tap = rig.tap;
    final delete = tap.indexOfSent(_isCramDelete);
    final list = tap.indexOfSent((c) => c.startsWith('enroll:list'));
    final publish = tap.indexOfSent((c) => _publishes(c, atSign));
    final again = tap.indexOfSent(_isCramDelete, from: delete + 1);
    expect([delete, list, publish, again], everyElement(greaterThan(-1)),
        reason: tap.transcript());
    expect(_accepted(tap, delete), isTrue);
    expect(_replyIndex(tap, delete), lessThan(list),
        reason: 'the CRAM secret was deleted before the revoke was asked for');
    expect(list, lessThan(publish),
        reason: 'the revoke was asked for before the key was published');
    expect(_accepted(tap, publish), isTrue);
    expect(_replyIndex(tap, publish), lessThan(again));
    final answer = _replyIndex(tap, again);
    print('LIVE second CRAM secret delete answered: '
        '${answer < 0 ? 'nothing' : tap.lines[answer].text}');
    expect(_accepted(tap, again), isTrue,
        reason: 'the atServer accepts the second delete of the CRAM secret');
  }, timeout: _timeout);

  test(
      'Onboarding records its completion as due before it writes the @keys '
      "document, records the CRAM secret's deletion, and deletes that record "
      'last', () async {
    const atSign = '@emoji🦄🛠';
    final rig = PasskeyRig(salt: 33);
    final otherPair = await apkamKeyPairFromSeed(
        Uint8List.fromList(List.generate(32, (i) => 200 - i)));
    final other = await AtAuthEnrollmentGateway(
            lookUps: rig.lookUps,
            finder: rig.finder,
            root: veRoot,
            app: 'wavi',
            device: 'othertool',
            clientOpener: rig.openClient)
        .activate(
            atSign: atSign, apkamKeyPair: otherPair, cram: cramKeyMap[atSign]!);
    addTearDown(other.close);
    final otherLookUp = await authenticatedLookUp(
        atSign,
        handshakeKeysIo(
            atSign,
            withApkamKey(
                AtKeys(atsign: Atsign(atSign)), other.enrollmentId, otherPair)),
        veRoot,
        lookUps: rig.lookUps,
        secondaryAddressFinder: rig.finder,
        enrollmentId: other.enrollmentId,
        clientConfig: const {});
    addTearDown(otherLookUp.close);
    Object? otherRead;
    Object? otherWrite;
    Object? otherDelete;
    final ownReads = <CompletionDue, CompletionDue?>{};

    final session = await rig
        .custody(
            gateway: _PausingGateway(rig.gateway(), (onboarding, state) async {
          if (state == CompletionDue.activated) {
            final record = CompletionDueRecord(
                RemoteSecondary(atSign, AtClientPreference(),
                    atLookUp: otherLookUp,
                    lookUps: rig.lookUps,
                    secondaryAddressFinder: rig.finder),
                atSign: atSign,
                enrollmentId: onboarding.enrollmentId);
            otherRead = await record.read().then<Object>(
                (read) => read ?? 'absent',
                onError: (Object e) => e);
            otherWrite = await record
                .write(CompletionDue.cramSecretDeleted)
                .then<Object>((_) => 'written', onError: (Object e) => e);
            otherDelete = await record
                .clear()
                .then<Object>((_) => 'deleted', onError: (Object e) => e);
          }
          ownReads[state] = await onboarding.completionDue();
        }))
        .onboard(atSign: atSign, cram: cramKeyMap[atSign]!);
    addTearDown(session.stop);
    final enrollmentId = session.client.enrollmentId!;

    final tap = rig.tap;
    bool isRecord(String c, String verb) =>
        c.startsWith('$verb:completion-due.$enrollmentId.a.__e@');
    final mark = tap
        .indexOfSent((c) => isRecord(c, 'update') && c.endsWith(' activated'));
    final document = tap.indexOfSent(_isDocumentPut);
    expect([mark, document], everyElement(greaterThan(-1)),
        reason: tap.transcript());
    expect(_accepted(tap, mark), isTrue);
    expect(_replyIndex(tap, mark), lessThan(document),
        reason: 'the atServer stored the record before the @keys document '
            'was sent');
    final delete = tap.indexOfSent(_isCramDelete);
    final rewrite = tap.indexOfSent(
        (c) => isRecord(c, 'update') && c.endsWith(' cram-deleted'),
        from: delete < 0 ? 0 : delete);
    final list = tap.indexOfSent((c) => c.startsWith('enroll:list'),
        from: rewrite < 0 ? 0 : rewrite);
    expect([delete, rewrite, list], everyElement(greaterThan(-1)),
        reason: tap.transcript());
    expect(_accepted(tap, delete), isTrue);
    expect(rewrite, greaterThan(_replyIndex(tap, delete)),
        reason: "the record said the CRAM secret was deleted after the CRAM "
            "secret's delete answered");
    expect(tap.lines[rewrite].connection, tap.lines[mark].connection,
        reason: 'the enrollment overwrote its own record');
    expect(_accepted(tap, rewrite), isTrue,
        reason: 'the atServer accepted the overwrite');
    expect(_replyIndex(tap, rewrite), lessThan(list),
        reason: 'and before the revoke');
    expect(
        ownReads,
        {
          CompletionDue.activated: CompletionDue.activated,
          CompletionDue.cramSecretDeleted: CompletionDue.cramSecretDeleted,
        },
        reason: "the enrollment's own reads found each value it wrote");
    final publish = tap.indexOfSent((c) => _publishes(c, atSign));
    expect(publish, greaterThan(-1), reason: tap.transcript());
    final clear = tap.indexOfSent((c) => isRecord(c, 'delete'), from: publish);
    expect(clear, greaterThan(_replyIndex(tap, publish)),
        reason: 'the record was deleted after the key was published');
    expect(tap.lines[clear].connection, tap.lines[mark].connection,
        reason: "the enrollment deleted it on its own connection");
    expect(_accepted(tap, clear), isTrue);
    expect(
        await CompletionDueRecord(session.client.getRemoteSecondary()!,
                atSign: atSign, enrollmentId: enrollmentId)
            .read(),
        isNull,
        reason: 'the record is gone once the onboarding returns');

    final namespaces = await _namespacesOf(session.client, other.enrollmentId,
        status: 'revoked');
    expect(namespaces,
        allOf(containsPair('*', 'rw'), containsPair('__manage', 'rw')),
        reason: 'the control: the other enrollment held *:rw and '
            '__manage:rw');
    for (final (verb, outcome) in [
      ('llookup', otherRead),
      ('update', otherWrite),
      ('delete', otherDelete)
    ]) {
      final sent = tap.indexOfSent((c) =>
          isRecord(c, verb) &&
          (verb != 'update' || c.endsWith(' cram-deleted')));
      expect(sent, greaterThan(-1), reason: tap.transcript());
      expect(tap.lines[sent].connection, isNot(tap.lines[mark].connection),
          reason: 'the control: the other enrollment sent it');
      final reply = _replyIndex(tap, sent);
      print('LIVE another enrollment\'s $verb of the record: '
          '${reply < 0 ? 'no reply' : tap.lines[reply].text}');
      expect(outcome, isA<UnAuthorizedException>(),
          reason: "another enrollment's $verb of the record is refused");
    }
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
    final interruptions = <String, (String, bool Function(String), Matcher)>{
      'after its enrollment was approved': (
        '@gateway2',
        (c) => c.contains('atkeys-lock.'),
        _asItIs,
      ),
      'after its @keys document was written': (
        '@jeremy',
        _isPointerPut,
        _asItIs,
      ),
      'after its pointer was written': ('@policy1', _isCramDelete, _incomplete),
    };
    for (final MapEntry(key: point, value: (atSign, cut, thrown))
        in interruptions.entries) {
      test(
          'An onboarding interrupted before the CRAM secret is deleted can '
          'be run again with the same secret: $point', () async {
        final rig = PasskeyRig(salt: 40 + point.length);
        await _interrupted(rig, atSign, cut, thrown);

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
    await _interrupted(rig, atSign, (c) => c.contains('atkeys-lock.'), _asItIs);
    final earlier = _requestedEnrollmentId(rig.tap)!;
    final mark = rig.tap.lines.length;

    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);

    final tap = rig.tap;
    final revoke = tap.indexOfSent(
        (c) => c.startsWith('enroll:revoke') && c.contains(earlier),
        from: mark);
    final delete = tap.indexOfSent(_isCramDelete, from: mark);
    final publish = tap.indexOfSent((c) => _publishes(c, atSign), from: mark);
    expect([revoke, delete, publish], everyElement(greaterThan(-1)),
        reason: tap.transcript());
    expect(_accepted(tap, delete), isTrue);
    expect(_replyIndex(tap, delete), lessThan(revoke),
        reason: 'the earlier enrollment was revoked after the CRAM secret was '
            'deleted');
    expect(_accepted(tap, revoke), isTrue);
    expect(_replyIndex(tap, revoke), lessThan(publish),
        reason: 'and before the new encryption public key was published');
    expect(
        await _approved(session.client, atSign), {session.client.enrollmentId});
  }, timeout: _timeout);

  test(
      'The retry of an interrupted onboarding publishes its own encryption '
      'public key over one already published', () async {
    const atSign = '@relay2';
    final rig = PasskeyRig(salt: 52);
    // An attempt cut at its delete of the CRAM secret leaves its enrollment
    // approved and its completion-due record, and the CRAM secret, for the
    // retry. Every attempt deletes the CRAM secret before it publishes, so a
    // key published by now is one published over CRAM, as another tool does.
    await _interrupted(rig, atSign, _isCramDelete, _incomplete);
    final earlier = _requestedEnrollmentId(rig.tap)!;
    final otherTools = _b("another tool's key");
    expect(await _publishOverCram(atSign, otherTools), startsWith('data:'),
        reason: 'another tool published a key over a CRAM connection');
    expect(await publicLookupReply(atSign, 'publickey'), 'data:$otherTools');

    final session = await _onboard(rig, atSign);
    addTearDown(session.stop);

    expect(session.client.enrollmentId, isNot(earlier),
        reason: 'the control: the retry made an enrollment of its own');
    final own = (await rig.storedDocument(atSign, session.client.enrollmentId!,
        rig.currentPrf))['aesEncryptPublicKey'];
    expect(own, isNot(otherTools));
    expect(await publicLookupReply(atSign, 'publickey'), 'data:$own');
    expect(
        await _approved(session.client, atSign), {session.client.enrollmentId},
        reason: "the retry revoked the interrupted attempt's enrollment");
  }, timeout: _timeout);

  test('A passkey left by an interrupted onboarding is refused as lost',
      () async {
    const atSign = '@gateway1';
    final rig = PasskeyRig(salt: 53);
    await _interrupted(rig, atSign, _isCramDelete, _incomplete);
    await (await _onboard(rig, atSign)).stop();

    rig.port.current = 1;
    await expectLater(
        rig.custody(hints: MemoryHints()).open(atSign: atSign),
        throwsA(isA<PasskeyLostException>()
            .having((e) => e.reason, 'reason', 'PKAM refused')),
        reason: "the first passkey's enrollment was revoked");
  }, timeout: _timeout);

  test(
      'A login after an onboarding interrupted once the CRAM secret is '
      'deleted opens its enrollment', () async {
    const atSign = '@gary';
    final rig = PasskeyRig(salt: 54);
    await _interrupted(rig, atSign,
        (_) => rig.tap.indexOfSent(_isCramDelete) >= 0, _incomplete);
    final onboarded = _requestedEnrollmentId(rig.tap)!;
    bool isRecord(String c, String verb) =>
        c.startsWith('$verb:completion-due.$onboarded.a.__e@');
    expect(rig.tap.dropped.first,
        allOf(startsWith('update:completion-due.'), endsWith(' cram-deleted')),
        reason: "the control: the record still says only 'activated', so the "
            'login finishes the activation from that state');
    final mark = rig.tap.lines.length;

    final session =
        await rig.custody(hints: MemoryHints()).open(atSign: atSign);
    addTearDown(session.stop);

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, onboarded);
    final tap = rig.tap;
    final publish = tap.indexOfSent((c) => _publishes(c, atSign), from: mark);
    final clear = tap.indexOfSent((c) => isRecord(c, 'delete'), from: mark);
    expect([publish, clear], everyElement(greaterThan(-1)),
        reason: tap.transcript());
    expect(_accepted(tap, publish), isTrue);
    expect(_replyIndex(tap, publish), lessThan(clear),
        reason: 'the record is deleted once the key is published');
    expect(_accepted(tap, clear), isTrue,
        reason: 'the login deleted the completion-due record');
    final own = (await rig.storedDocument(
        atSign, onboarded, rig.currentPrf))['aesEncryptPublicKey'];
    expect(await publicLookupReply(atSign, 'publickey'), 'data:$own',
        reason: "the login published the document's key");
    expect(await _cramLogin(atSign), startsWith('refused'),
        reason: 'the CRAM secret stays deleted');
  }, timeout: _timeout);

  test(
      'A login after an onboarding that stopped before deleting the CRAM '
      'secret deletes it before it opens the client, and publishes the '
      "document's encryption public key", () async {
    const atSign = '@sachin';
    final rig = PasskeyRig(salt: 55);
    await _interrupted(rig, atSign, _isCramDelete, _incomplete);
    expect(await publicLookupReply(atSign, 'publickey'), contains('AT0015'),
        reason: 'the onboarding published no encryption public key');
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
    final own = (await rig.storedDocument(atSign, session.client.enrollmentId!,
        rig.currentPrf))['aesEncryptPublicKey'];
    expect(await publicLookupReply(atSign, 'publickey'), 'data:$own',
        reason: "the login published the document's encryption public key");
  }, timeout: _timeout);

  test('A login with saved hints sends no activation completion', () async {
    const atSign = '@egcreditbureau🛠';
    final rig = PasskeyRig(salt: 57);
    final device = MemoryHints();
    await (await rig
            .custody(hints: device)
            .onboard(atSign: atSign, cram: cramKeyMap[atSign]!))
        .stop();
    expect(device.ids[atSign], isNotNull,
        reason: 'the control: the onboarding saved its hints');
    expect(rig.tap.indexOfSent(_isCramDelete), isNot(-1),
        reason: 'the control: the onboarding sent a CRAM secret delete');
    expect(rig.tap.indexOfSent((c) => _publishes(c, atSign)), isNot(-1),
        reason: 'the control: the onboarding published its encryption '
            'public key');
    final mark = rig.tap.lines.length;

    final session = await rig.custody(hints: device).open(atSign: atSign);
    addTearDown(session.stop);

    expect(session.client.connection.current.isOnline, isTrue);
    expect(rig.tap.indexOfSent((c) => c.startsWith('pkam:'), from: mark),
        isNot(-1),
        reason: 'the control: the login authenticated through the tap');
    expect(rig.tap.indexOfSent(_isCramDelete, from: mark), -1,
        reason: 'a login with saved hints sends no CRAM secret delete');
    expect(rig.tap.indexOfSent((c) => _publishes(c, atSign), from: mark), -1,
        reason: 'a login with saved hints publishes no encryption public key');
  }, timeout: _timeout);
}

const _timeout = Timeout(Duration(minutes: 3));

/// The ttl each take of the @keys lock lasts.
const _lockTtl = Duration(seconds: 10);

/// Long enough for a lock taken before it to have expired.
const _pastTheLock = Duration(seconds: 11);

/// Long enough for a lock taken before it to have less than half its ttl
/// left.
const _pastHalfTheLock = Duration(seconds: 6);

/// How much later than the command itself the tap may stamp a sent line.
const _tapSlack = Duration(milliseconds: 250);

String _b(String s) => base64Encode(utf8.encode(s));

Future<PasskeySession> _onboard(PasskeyRig rig, String atSign) =>
    rig.custody().onboard(atSign: atSign, cram: cramKeyMap[atSign]!);

/// What an onboarding cut once its pointer is written throws.
final _incomplete = isA<PasskeyOnboardingIncompleteException>();

/// What an onboarding cut before its pointer is written throws: the failure
/// as it is.
final _asItIs = isNot(isA<PasskeyOnboardingIncompleteException>());

/// Runs an onboarding of [atSign] whose network is cut at the first command
/// [cut] matches, expects it to throw what [thrown] matches, and then
/// restores the network.
Future<void> _interrupted(PasskeyRig rig, String atSign,
    bool Function(String) cut, Matcher thrown) async {
  rig.tap.dropOn = cut;
  await expectLater(_onboard(rig, atSign), throwsA(thrown));
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

/// Whether the line at [i] is a take of the @keys lock the atServer granted.
bool _isAcceptedTake(WireTap tap, int i) =>
    tap.lines[i].sent &&
    tap.lines[i].text.contains('atkeys-lock.') &&
    _accepted(tap, i);

bool _isLockTake(String c) =>
    c.startsWith('update:') && c.contains('atkeys-lock.');

/// The index of the first take of the @keys lock at or after [from] that the
/// atServer refused, or -1.
int _refusedTakeAfter(WireTap tap, int from) {
  for (var i = from; i < tap.lines.length; i++) {
    final l = tap.lines[i];
    if (l.sent && _isLockTake(l.text) && !_accepted(tap, i)) return i;
  }
  return -1;
}

/// The index of the first command at or after [from] sent on a connection
/// [on] picks that [matches], and that the atServer accepted when [accepted]
/// is true; or -1.
int _indexOn(WireTap tap, bool Function(int connection) on,
    bool Function(String command) matches, int from,
    {bool accepted = false}) {
  for (var i = from; i < tap.lines.length; i++) {
    final l = tap.lines[i];
    if (l.sent &&
        on(l.connection) &&
        matches(l.text) &&
        (!accepted || _accepted(tap, i))) {
      return i;
    }
  }
  return -1;
}

/// The index of the last granted take of the @keys lock before [before], or
/// -1.
int _acceptedTakeBefore(WireTap tap, int before) {
  for (var i = before - 1; i >= 0; i--) {
    if (_isAcceptedTake(tap, i)) return i;
  }
  return -1;
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

/// How many takes of the @keys lock sent at or after [from] the atServer has
/// answered with a refusal; a take not yet answered is not counted.
int _answeredRefusals(WireTap tap, int from) {
  var refused = 0;
  for (var i = from; i < tap.lines.length; i++) {
    final l = tap.lines[i];
    if (l.sent &&
        l.text.contains('atkeys-lock.') &&
        _replyIndex(tap, i) >= 0 &&
        !_accepted(tap, i)) {
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

/// The namespaces of the enrollment [enrollmentId], whose status is
/// [status], as [client] lists them.
Future<Map<String, dynamic>> _namespacesOf(AtClient client, String enrollmentId,
    {required String status}) async {
  final reply = await client.getRemoteSecondary()!.executeCommand(
      'enroll:list:{"enrollmentStatusFilter":["$status"]}\n',
      auth: true);
  final listed =
      jsonDecode(reply!.substring(reply.indexOf('data:') + 5)) as Map;
  for (final MapEntry(:key, :value) in listed.entries) {
    if ((key as String).split('.').first == enrollmentId) {
      return (value as Map)['namespace'] as Map<String, dynamic>;
    }
  }
  throw StateError('no $status enrollment $enrollmentId');
}

/// `accepted` when a `cram:` login of [atSign] with its CRAM secret succeeds
/// on a connection of its own, `refused:` and the reason when the atServer
/// refuses it, else `failed:` and the reason: a probe that could not connect,
/// timed out or failed otherwise says nothing about the CRAM secret.
Future<String> _cramLogin(String atSign) async {
  final lookUp = secureSocketLookUps()(
      atSign: atSign, rootDomain: veRoot, authenticator: null);
  try {
    lookUp.authenticator =
        authenticatorForCramSecret(atSign, cramKeyMap[atSign]!);
    return await lookUp.pkamAuthenticate() ? 'accepted' : 'refused: false';
  } on UnAuthenticatedException catch (e) {
    return 'refused: $e';
  } on AtLookUpException catch (e) {
    return e.errorCode == 'AT0401' ? 'refused: $e' : 'failed: $e';
  } on Exception catch (e) {
    return 'failed: $e';
  } finally {
    await lookUp.close();
  }
}

/// The reply to an `update` of [atSign]'s public `publickey` to [value], sent
/// on a CRAM connection of its own, as another activation tool sends it.
Future<String> _publishOverCram(String atSign, String value) async {
  final lookUp = secureSocketLookUps()(
      atSign: atSign, rootDomain: veRoot, authenticator: null);
  try {
    lookUp.authenticator =
        authenticatorForCramSecret(atSign, cramKeyMap[atSign]!);
    if (!await lookUp.pkamAuthenticate()) return 'refused: false';
    final command =
        'update:ttr:-1:isEncrypted:false:public:publickey$atSign $value\n';
    return '${await lookUp.executeCommand(command, auth: true)}';
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
/// and a store over it, as another device of the enrollment holds. The store
/// uses the documents [wrap] returns for the session's, when given.
Future<({AtServerAtKeysIo store, Future<void> Function() close})> _otherWriter(
    PasskeyRig rig, String atSign, String enrollmentId, Uint8List prf,
    {EnrollmentDocumentStore Function(EnrollmentDocumentStore documents)?
        wrap}) async {
  final keys = await deriveFor(prf, atSign);
  final pair = await apkamKeyPairFromSeed(keys.authSeed);
  final session = await rig.gateway().authenticate(
      atSign: atSign, enrollmentId: enrollmentId, apkamKeyPair: pair);
  final store = AtServerAtKeysIo(
      documents: wrap?.call(session.documents) ?? session.documents,
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

/// [_inner], whose put completes [reached] and then waits for [release]
/// before it is sent.
class _HeldPut implements EnrollmentDocumentStore {
  _HeldPut(this._inner, {required this.reached, required this.release});

  final EnrollmentDocumentStore _inner;
  final Completer<void> reached;
  final Completer<void> release;

  @override
  Future<String?> get(String atSign, String enrollmentId) =>
      _inner.get(atSign, enrollmentId);

  @override
  Future<void> put(String atSign, String enrollmentId, String document) async {
    if (!reached.isCompleted) reached.complete();
    await release.future;
    return _inner.put(atSign, enrollmentId, document);
  }

  @override
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
          {required Duration ttl}) =>
      _inner.tryLock(atSign, enrollmentId, ttl: ttl);
}

/// A gateway whose activations, each time they write their completion-due
/// record, run [onRecorded] before the onboarding goes on.
class _PausingGateway implements EnrollmentGateway {
  _PausingGateway(this._inner, this.onRecorded);

  final EnrollmentGateway _inner;
  final Future<void> Function(EnrollmentSession onboarding, CompletionDue state)
      onRecorded;

  @override
  String get device => _inner.device;

  @override
  Future<EnrollmentSession> authenticate(
          {required String atSign,
          required String enrollmentId,
          required ApkamKeyPair apkamKeyPair}) =>
      _inner.authenticate(
          atSign: atSign,
          enrollmentId: enrollmentId,
          apkamKeyPair: apkamKeyPair);

  @override
  Future<EnrollmentSession> activate(
          {required String atSign,
          required ApkamKeyPair apkamKeyPair,
          required String cram}) async =>
      _PausingSession(
          await _inner.activate(
              atSign: atSign, apkamKeyPair: apkamKeyPair, cram: cram),
          onRecorded);
}

/// [_inner], running [_onRecorded] each time its completion-due record is
/// written.
class _PausingSession implements EnrollmentSession {
  _PausingSession(this._inner, this._onRecorded);

  final EnrollmentSession _inner;
  final Future<void> Function(EnrollmentSession onboarding, CompletionDue state)
      _onRecorded;

  @override
  String get enrollmentId => _inner.enrollmentId;

  @override
  EnrollmentDocumentStore get documents => _inner.documents;

  @override
  EnrollmentPointerStore get pointers => _inner.pointers;

  @override
  Future<Map<String, dynamic>> atKeys() => _inner.atKeys();

  @override
  Future<PublishedEncryptionKey> publishedEncryptionKey(
          Map<String, dynamic> atKeys) =>
      _inner.publishedEncryptionKey(atKeys);

  @override
  Future<void> revokeOtherEnrollments() => _inner.revokeOtherEnrollments();

  @override
  Future<void> completeActivation(Map<String, dynamic> atKeys) =>
      _inner.completeActivation(atKeys);

  @override
  Future<void> recordCompletionDue(CompletionDue state) async {
    await _inner.recordCompletionDue(state);
    await _onRecorded(this, state);
  }

  @override
  Future<CompletionDue?> completionDue() => _inner.completionDue();

  @override
  Future<void> clearCompletionDue() => _inner.clearCompletionDue();

  @override
  Future<AtClient> openClient(WrittenAtKeysIo keysIo) =>
      _inner.openClient(keysIo);

  @override
  Future<void> close() => _inner.close();
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
