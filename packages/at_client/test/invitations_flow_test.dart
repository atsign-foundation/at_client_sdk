// ignore_for_file: experimental_member_use, invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:mocktail/mocktail.dart' show Fake;
import 'package:test/test.dart';

const _ns = 'my_app';

/// The atServers of several atSigns, in memory. Each holds its own records,
/// and a cached copy of every record shared with it.
class _Servers {
  final _stores = <String, Map<String, _Record>>{};

  /// Key-name fragments whose next put fails, as on a dropped connection.
  final failOnce = <String>[];

  /// Key-name fragments whose puts always fail, as for a recipient that
  /// cannot be sent to.
  final failAlways = <String>[];

  Map<String, _Record> of(String atSign) =>
      _stores.putIfAbsent(atSign, () => {});

  _Record? find(String atSign, String name) {
    final record = of(atSign)[name];
    return record == null || record.expired ? null : record;
  }

  /// Puts a collection item straight into [atSign]'s store, as though it had
  /// arrived from elsewhere.
  void plant(String atSign, String name, String type, Object? obj) =>
      of(atSign)[name] = _Record(jsonEncode({'type': type, 'obj': obj}));

  /// Puts a lock record straight into [atSign]'s store.
  void plantLock(String atSign, String name, String value) =>
      of(atSign)['$name.locks.invitations.$_ns$atSign'] =
          _Record(value, immutable: true);

  Iterable<MapEntry<String, _Record>> locks(String atSign) =>
      of(atSign).entries.where((e) => e.key.contains('.locks.invitations.'));
}

class _Record {
  final String value;
  final int? ttl;
  final bool immutable;
  final DateTime createdAt = DateTime.now().toUtc();

  _Record(this.value, {this.ttl, this.immutable = false});

  DateTime? get expiresAt =>
      ttl == null ? null : createdAt.add(Duration(milliseconds: ttl!));

  bool get expired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);
}

/// A client of one atSign whose atServer is in [_Servers]. It validates keys
/// and refuses a second write to an immutable record, as an atServer does;
/// anything else it was not written for throws.
class _Client extends Fake implements AtClient {
  final _Servers servers;
  final String me;
  final _collections = <String, Object>{};

  _Client(this.servers, this.me);

  @override
  Atsign get atSign => me.toAtsign();

  @override
  String? getCurrentAtSign() => me;

  @override
  Future<AtCollection<T>> collection<T>(
    String namespace,
    Duration defaultExpiration, {
    EventSource eventSource = EventSource.both,
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
    bool cleanupOrphansOnCreation = false,
  }) async =>
      _collections.putIfAbsent(
        namespace,
        () => collectionWithInjectedNotifications<T>(
          this,
          namespace,
          defaultExpiration,
          notifications: const Stream.empty(),
          fromJson: fromJson,
          typeTag: typeTag,
        ),
      ) as AtCollection<T>;

  @override
  Future<bool> put(AtKey key, dynamic value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    final name = key.toString();
    final validation = AtKeyValidators.get().validate(
      name,
      ValidationContext()
        ..atSign = me
        ..validateOwnership = true
        ..enforceNamespace = true,
    );
    if (!validation.isValid) throw AtKeyException(validation.failureReason);
    if (servers.failAlways.any(name.contains)) {
      throw AtClientException.message('Could not reach the recipient');
    }
    final once = servers.failOnce.where(name.contains).firstOrNull;
    if (once != null) {
      servers.failOnce.remove(once);
      throw AtClientException.message('Connection lost');
    }
    if (servers.find(me, name)?.immutable == true) {
      throw AtClientException.message('Immutable records may not be updated');
    }
    final record = _Record(value as String,
        ttl: key.metadata.ttl, immutable: key.metadata.immutable);
    servers.of(me)[name] = record;
    final to = key.sharedWith;
    if (to != null && _at(to) != me) {
      servers.of(_at(to))['cached:$name'] = record;
    }
    return true;
  }

  @override
  Future<AtValue> get(AtKey key,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions}) async {
    final name = key.toString();
    var record = servers.find(me, name);
    if (record == null && name.startsWith('public:') && key.sharedBy != null) {
      record = servers.find(_at(key.sharedBy!), name);
    }
    if (record == null) throw AtKeyNotFoundException('$name does not exist');
    return AtValue()
      ..value = record.value
      ..metadata = (Metadata()
        ..createdAt = record.createdAt
        ..expiresAt = record.expiresAt
        ..ttl = record.ttl
        ..immutable = record.immutable);
  }

  @override
  Future<bool> delete(AtKey key,
      {bool isDedicated = false,
      DeleteRequestOptions? deleteRequestOptions}) async {
    final name = key.toString();
    servers.of(me).remove(name);
    final to = key.sharedWith;
    if (to != null) servers.of(_at(to)).remove('cached:$name');
    return true;
  }

  @override
  Future<List<AtKey>> getAtKeys({
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool showHiddenKeys = false,
    bool useRemoteAtServer = false,
  }) async {
    final matches = RegExp(regex ?? '.*');
    return [
      for (final entry in servers.of(me).entries)
        if (!entry.value.expired &&
            (showHiddenKeys || !entry.key.startsWith('public:_')) &&
            matches.hasMatch(entry.key))
          AtKey.fromString(entry.key),
    ];
  }

  static String _at(String atSign) =>
      atSign.startsWith('@') ? atSign : '@$atSign';
}

void main() {
  late _Servers servers;
  late AtClientInvitations alice;
  late AtClientInvitations bob;

  AtClientInvitations clientOf(String atSign) =>
      AtClientInvitations(_Client(servers, atSign), invitationsNamespace: _ns);

  String wrongCode(String code) => code == '111111' ? '222222' : '111111';

  Future<SentInvitation> sent(String id) async =>
      (await (await alice.sentInvitations).get(id, alice.me)).obj;

  Future<List<InvitationOutcome>> pass() async =>
      [for (final d in await alice.processAcceptances()) d.outcome];

  setUp(() {
    servers = _Servers();
    alice = clientOf('@alice');
    bob = clientOf('@bob');
  });

  group('processAcceptances', () {
    test('accepts the right code, and the invitee opens the content', () async {
      final created = await alice.invite(
          publicDetails: {'from': 'Alice'}, content: {'text': 'secret'});
      await bob
          .accept(created.link, created.code, details: {'name': 'Bob Brown'});

      expect(await pass(), [InvitationOutcome.accepted]);
      final accepted = await sent(created.link.id);
      expect(accepted.status, SentInvitationStatus.accepted);
      expect(accepted.acceptedBy, bob.me);
      expect(accepted.acceptanceDetails, {'name': 'Bob Brown'});

      final connected = await bob.processConnections();
      expect(connected.single.obj.content, {'text': 'secret'});
      expect(await pass(), isEmpty,
          reason: 'an acceptance of a decided invitation is not reported '
              'again');
    });

    test(
        'shares the content key only with an atSign whose acceptance '
        'carries the code', () async {
      final created = await alice.invite(content: {'text': 'secret'});
      final id = created.link.id;
      servers.plantLock('@alice', 'outcome.$id', 'accepted:@mallory');

      await alice.processAcceptances();

      expect(
          servers.of('@mallory').keys.where((k) => k.contains('.connections.')),
          isEmpty,
          reason: 'an outcome record the atServer holds is not proof that '
              'the atSign it names sent the code');
      expect((await sent(id)).status, SentInvitationStatus.pending);
    });

    test('skips a record it cannot read, and handles the others', () async {
      final created = await alice.invite();
      await bob.accept(created.link, created.code);
      servers.plant(
          '@alice',
          'cached:@alice:bad.acceptances.invitations.$_ns@mallory',
          'InvitationAcceptance',
          {'invitationId': 1, 'code': 'x'});

      expect(await pass(), [InvitationOutcome.accepted],
          reason: 'any atSign can share an unreadable acceptance');
    });

    test('counts an acceptance with an overlong id as a wrong code', () async {
      final created = await alice.invite();
      servers.plant(
          '@alice',
          'cached:@alice:${'x' * 180}.acceptances.invitations.$_ns@mallory',
          'InvitationAcceptance', {
        'invitationId': created.link.id,
        'code': wrongCode(created.code),
      });

      expect(await pass(), [InvitationOutcome.wrongCode],
          reason: 'the invitee chooses the acceptance id, and the claim built '
              'from it must still be a valid key');
    });

    test('accepts on a later pass when recording the decision failed',
        () async {
      final created = await alice.invite();
      await bob.accept(created.link, created.code);
      servers.failOnce.add('outcome.');

      expect(await pass(), isEmpty);
      expect(await pass(), [InvitationOutcome.accepted],
          reason: 'a failure before the decision is recorded must not strand '
              'a correct acceptance');
    });

    test('the fifth wrong code burns the invitation', () async {
      final created = await alice.invite();
      for (var i = 1; i <= Invitations.attemptLimit; i++) {
        await clientOf('@m$i').accept(created.link, wrongCode(created.code));
      }

      expect(await pass(), [
        ...List.filled(
            Invitations.attemptLimit - 1, InvitationOutcome.wrongCode),
        InvitationOutcome.burned,
      ]);

      servers.plant(
          '@alice',
          'cached:@alice:late.acceptances.invitations.$_ns@bob',
          'InvitationAcceptance',
          {'invitationId': created.link.id, 'code': created.code});
      expect(await pass(), isEmpty);
      expect((await sent(created.link.id)).status, SentInvitationStatus.burned);
    });

    test(
        'burns on the next wrong code when every slot was taken without a '
        'burn', () async {
      final created = await alice.invite();
      final id = created.link.id;
      for (var slot = 1; slot <= Invitations.attemptLimit; slot++) {
        servers.plantLock('@alice', 'attempt$slot.$id', 'wrong');
      }
      await clientOf('@m1').accept(created.link, wrongCode(created.code));

      expect(await pass(), [InvitationOutcome.burned],
          reason: 'a client that stopped before recording the burn must not '
              'lift the attempt limit');

      servers.plant(
          '@alice',
          'cached:@alice:late.acceptances.invitations.$_ns@bob',
          'InvitationAcceptance',
          {'invitationId': id, 'code': created.code});
      expect(await pass(), isEmpty);
      expect((await sent(id)).status, SentInvitationStatus.burned);
    });

    test('does not count wrong codes once the invitation is decided', () async {
      final created = await alice.invite();
      await bob.accept(created.link, created.code);
      expect(await pass(), [InvitationOutcome.accepted]);

      for (var i = 1; i <= Invitations.attemptLimit; i++) {
        servers.plant(
            '@alice',
            'cached:@alice:late$i.acceptances.invitations.$_ns@m$i',
            'InvitationAcceptance',
            {'invitationId': created.link.id, 'code': wrongCode(created.code)});
      }

      expect(await pass(), isEmpty);
      expect(servers.locks('@alice').map((e) => e.key),
          everyElement(isNot(contains('attempt'))));
    });

    test('one invitee it cannot share with does not hold up the others',
        () async {
      final forDave = await alice.invite();
      final forBob = await alice.invite();
      await clientOf('@dave').accept(forDave.link, forDave.code);
      await bob.accept(forBob.link, forBob.code);
      servers.failAlways.add('@dave:');

      final decided = await alice.processAcceptances();
      expect([
        for (final d in decided)
          if (d.acceptance.owner == bob.me) d.outcome
      ], [
        InvitationOutcome.accepted
      ]);
      expect(
          (await sent(forDave.link.id)).status, SentInvitationStatus.pending);

      servers.failAlways.clear();
      await alice.processAcceptances();
      final finished = await sent(forDave.link.id);
      expect(finished.status, SentInvitationStatus.accepted,
          reason: 'a later pass finishes what the failed share left');
      expect(finished.acceptedBy, '@dave'.toAtsign());
    });

    test('finishes a revoke that stopped part way', () async {
      final created = await alice.invite();
      final id = created.link.id;
      servers.plantLock('@alice', 'outcome.$id', 'revoked');

      await alice.processAcceptances();

      expect((await sent(id)).status, SentInvitationStatus.revoked);
      expect(
          servers.find('@alice', 'public:_$id.invitations.$_ns@alice'), isNull);
    });

    test('its lock records expire with the invitation', () async {
      final created = await alice.invite();
      final id = created.link.id;
      await clientOf('@m1').accept(created.link, wrongCode(created.code));
      expect(await pass(), [InvitationOutcome.wrongCode]);
      await bob.accept(created.link, created.code);
      expect(await pass(), contains(InvitationOutcome.accepted));

      final item = await (await alice.sentInvitations).get(id, alice.me);
      final locks = servers.locks('@alice').toList();
      expect(locks.map((e) => e.key.split('.').first),
          unorderedMatches(['attempt1', 'outcome', 'claim']));
      for (final lock in locks) {
        final expiresAt = lock.value.expiresAt;
        expect(expiresAt, isNotNull, reason: '${lock.key} never expires');
        expect(
            expiresAt!.difference(item.expiresAt).inSeconds.abs(), lessThan(60),
            reason: lock.key);
      }
    });
  });

  group('processConnections', () {
    test('completes only an invitation this atSign accepted', () async {
      final mallory = clientOf('@mallory');
      final created = await mallory.invite();
      await bob.preview(created.link);
      servers.plant(
          '@bob',
          'cached:@bob:${created.link.id}.connections.invitations.$_ns@mallory',
          'InvitationConnection',
          {'invitationId': created.link.id});

      expect(await bob.processConnections(), isEmpty,
          reason: 'an inviter who knows the invitee must not make them a '
              'contact without their acceptance');
    });

    test('skips a confirmation it cannot complete, and completes the others',
        () async {
      final carol = clientOf('@carol');
      final fromAlice = await alice.invite(content: {'text': 'from Alice'});
      final fromCarol = await carol.invite(content: {'text': 'from Carol'});
      await bob.accept(fromAlice.link, fromAlice.code);
      await bob.accept(fromCarol.link, fromCarol.code);
      await alice.processAcceptances();
      servers.plant(
          '@bob',
          'cached:@bob:${fromCarol.link.id}.connections.invitations.$_ns@carol',
          'InvitationConnection', {
        'invitationId': fromCarol.link.id,
        'contentKey': InvitationKey.mint().base64,
      });
      servers.plant(
          '@bob',
          'cached:@bob:bad.connections.invitations.$_ns@mallory',
          'InvitationConnection',
          {'invitationId': 7});

      final connected = await bob.processConnections();

      expect([
        for (final c in connected) c.obj.content
      ], [
        {'text': 'from Alice'}
      ]);
    });
  });
}
