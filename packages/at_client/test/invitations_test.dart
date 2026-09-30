// ignore_for_file: experimental_member_use
import 'dart:convert';

import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  const id = '0123456789abcdef0123456789abcdef';

  group('InvitationLink', () {
    test('parses a full link, with the invitation in the fragment', () {
      final link =
          InvitationLink.parse('https://invite.example.com/i#@alice/$id');

      expect(link.inviter, '@alice');
      expect(link.id, id);
    });

    test('parses the bare fragment, and a percent-encoded one', () {
      expect(InvitationLink.parse('@alice/$id').id, id);
      expect(
          InvitationLink.parse('https://x/i#%40alice%2F$id').inviter, '@alice');
    });

    test('refuses anything that is not a whole invitation', () {
      for (final text in [
        'https://invite.example.com/i',
        '@alice/0123',
        'alice/$id',
        '@alice/${id.toUpperCase()}',
        '@alice/$id/extra',
      ]) {
        expect(() => InvitationLink.parse(text), throwsFormatException,
            reason: text);
      }
    });

    test('the link format is frozen: the id is in the fragment', () {
      // NOTE: a landing page and every app parse this shape.
      expect(
          InvitationLink(inviter: '@alice'.toAtsign(), id: id)
              .toUrl('https://invite.example.com'),
          'https://invite.example.com/i#@alice/$id');
    });
  });

  group('the preview record', () {
    test('its key is frozen', () {
      // NOTE: the invitee's client reads it by this name, unauthenticated.
      expect(invitationPreviewKey('@alice'.toAtsign(), id, 'my_app').toString(),
          'public:_$id.invitations.my_app@alice');
    });

    test('its JSON is frozen', () {
      final preview = InvitationPreview(
        publicDetails: {'from': 'Alice', 'message': 'Join me'},
        expiresAt: DateTime.utc(2026, 10, 6, 21),
        content: const SealedInvitationContent(
            nonce: 'bm9uY2U=', ciphertext: 'Y3Q='),
      );

      expect(
          jsonEncode(preview.toJson()),
          '{"v":1,"publicDetails":{"from":"Alice","message":"Join me"},'
          '"expiresAt":"2026-10-06T21:00:00.000Z",'
          '"content":{"nonce":"bm9uY2U=","ciphertext":"Y3Q="}}');
    });

    test('a preview reads back the app details it was written with', () {
      final json =
          jsonDecode('{"v":1,"publicDetails":{"from":"Alice","tags":["a","b"]},'
              '"expiresAt":"2026-10-06T21:00:00.000Z"}');

      final preview = InvitationPreview.fromJson(json);

      expect(preview.publicDetails, {
        'from': 'Alice',
        'tags': ['a', 'b']
      });
      expect(preview.content, isNull);
    });

    test('a preview of an unknown version is refused', () {
      expect(
          () => InvitationPreview.fromJson({
                'v': 2,
                'publicDetails': <String, dynamic>{},
                'expiresAt': '2026-10-06T21:00:00.000Z',
              }),
          throwsFormatException);
    });
  });

  group('InvitationKey', () {
    test('opens what it sealed for the same invitation', () async {
      final key = InvitationKey.mint();
      final sealed =
          await key.seal('the recipe', inviter: '@alice', invitationId: id);

      expect(
          await InvitationKey.fromBase64(key.base64)
              .open(sealed, inviter: '@alice', invitationId: id),
          'the recipe');
    });

    test('refuses content moved to another invitation or inviter', () async {
      final key = InvitationKey.mint();
      final sealed =
          await key.seal('the recipe', inviter: '@alice', invitationId: id);

      await expectLater(
          key.open(sealed,
              inviter: '@alice', invitationId: id.replaceFirst('0', '1')),
          throwsA(isA<AtDecryptionException>()));
      await expectLater(key.open(sealed, inviter: '@mallory', invitationId: id),
          throwsA(isA<AtDecryptionException>()));
    });

    test('its encryption is frozen: AES-256-GCM bound to inviter/id', () async {
      // NOTE: the invitee's app, whichever build, opens what the inviter's
      // sealed.
      const sealed = SealedInvitationContent(
          nonce: 'mLMShcGxtp9RhpUp',
          ciphertext: 'KsPKso/drdOiD0FkCF5RlMwGxyKmnbIhJk0sZL2yrxbX');

      expect(
          await InvitationKey.fromBase64(
                  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=')
              .open(sealed, inviter: '@alice', invitationId: id),
          '{"text":"secret"}');
    });

    test('refuses a different key', () async {
      final sealed = await InvitationKey.mint()
          .seal('the recipe', inviter: '@alice', invitationId: id);

      await expectLater(
          InvitationKey.mint()
              .open(sealed, inviter: '@alice', invitationId: id),
          throwsA(isA<AtDecryptionException>()));
    });
  });

  group('records round-trip through JSON', () {
    test('SentInvitation', () {
      final sent = SentInvitation(
        code: '012345',
        expiresAt: DateTime.utc(2026, 10, 6),
        publicDetails: {'from': 'Alice'},
        contentKey: 'a2V5',
        status: SentInvitationStatus.accepted,
        acceptedBy: '@bob'.toAtsign(),
        acceptanceDetails: {'name': 'Bob'},
      );

      final back =
          SentInvitation.fromJson(jsonDecode(jsonEncode(sent.toJson())));

      expect(back.toJson(), sent.toJson());
      expect(back.code, '012345', reason: 'a code keeps its leading zero');
      expect(back.acceptanceDetails, {'name': 'Bob'});
    });

    test('ReceivedInvitation', () {
      final received = ReceivedInvitation(
        inviter: '@alice'.toAtsign(),
        publicDetails: {'from': 'Alice'},
        expiresAt: DateTime.utc(2026, 10, 6),
        sealedContent:
            const SealedInvitationContent(nonce: 'bg==', ciphertext: 'Yw=='),
        status: ReceivedInvitationStatus.connected,
        content: {'recipe': 'lemon cake'},
      );

      final back = ReceivedInvitation.fromJson(
          jsonDecode(jsonEncode(received.toJson())));

      expect(back.toJson(), received.toJson());
      expect(back.content, {'recipe': 'lemon cake'});
    });

    test('InvitationAcceptance, with and without details', () {
      const acceptance = InvitationAcceptance(
          invitationId: id, code: '012345', details: {'name': 'Bob'});

      expect(
          InvitationAcceptance.fromJson(
                  jsonDecode(jsonEncode(acceptance.toJson())))
              .details,
          {'name': 'Bob'});
      expect(
          InvitationAcceptance.fromJson({'invitationId': id, 'code': '1'})
              .details,
          isEmpty);
    });
  });

  group('record JSON is frozen', () {
    // NOTE: the other party's app, and this atSign's other clients, read
    // these records whichever build wrote them.
    void frozen<T>(T record, Map<String, dynamic> Function(T) toJson,
        T Function(Map<String, dynamic>) fromJson, String json) {
      expect(jsonEncode(toJson(record)), json);
      expect(jsonEncode(toJson(fromJson(jsonDecode(json)))), json);
    }

    test('SentInvitation', () {
      frozen(
          SentInvitation(
            code: '012345',
            expiresAt: DateTime.utc(2026, 10, 6),
            publicDetails: {'from': 'Alice'},
            contentKey: 'a2V5',
            status: SentInvitationStatus.accepted,
            acceptedBy: '@bob'.toAtsign(),
            acceptanceDetails: {'name': 'Bob'},
          ),
          (r) => r.toJson(),
          SentInvitation.fromJson,
          '{"code":"012345","expiresAt":"2026-10-06T00:00:00.000Z",'
          '"publicDetails":{"from":"Alice"},"contentKey":"a2V5",'
          '"status":"accepted","acceptedBy":"@bob",'
          '"acceptanceDetails":{"name":"Bob"}}');
    });

    test('ReceivedInvitation', () {
      frozen(
          ReceivedInvitation(
            inviter: '@alice'.toAtsign(),
            publicDetails: {'from': 'Alice'},
            expiresAt: DateTime.utc(2026, 10, 6),
            sealedContent: const SealedInvitationContent(
                nonce: 'bg==', ciphertext: 'Yw=='),
            status: ReceivedInvitationStatus.connected,
            content: {'recipe': 'lemon cake'},
          ),
          (r) => r.toJson(),
          ReceivedInvitation.fromJson,
          '{"inviter":"@alice","publicDetails":{"from":"Alice"},'
          '"expiresAt":"2026-10-06T00:00:00.000Z",'
          '"sealedContent":{"nonce":"bg==","ciphertext":"Yw=="},'
          '"status":"connected","content":{"recipe":"lemon cake"}}');
    });

    test('InvitationAcceptance', () {
      frozen(
          const InvitationAcceptance(
              invitationId: id, code: '012345', details: {'name': 'Bob'}),
          (r) => r.toJson(),
          InvitationAcceptance.fromJson,
          '{"invitationId":"$id","code":"012345","details":{"name":"Bob"}}');
    });

    test('InvitationConnection', () {
      frozen(
          const InvitationConnection(invitationId: id, contentKey: 'a2V5'),
          (r) => r.toJson(),
          InvitationConnection.fromJson,
          '{"invitationId":"$id","contentKey":"a2V5"}');
      frozen(const InvitationConnection(invitationId: id), (r) => r.toJson(),
          InvitationConnection.fromJson, '{"invitationId":"$id"}');
    });

    test('the statuses', () {
      expect(SentInvitationStatus.values.map((s) => s.name),
          ['pending', 'accepted', 'burned', 'revoked']);
      expect(ReceivedInvitationStatus.values.map((s) => s.name),
          ['previewed', 'accepted', 'connected']);
    });
  });
}
