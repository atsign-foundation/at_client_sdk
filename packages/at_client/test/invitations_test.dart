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
        inviterName: 'Alice',
        message: 'Join me',
        expiresAt: DateTime.utc(2026, 10, 6, 21),
        content: const SealedInvitationContent(
            nonce: 'bm9uY2U=', ciphertext: 'Y3Q='),
      );

      expect(
          jsonEncode(preview.toJson()),
          '{"v":1,"inviterName":"Alice","message":"Join me",'
          '"expiresAt":"2026-10-06T21:00:00.000Z",'
          '"content":{"nonce":"bm9uY2U=","ciphertext":"Y3Q="}}');
    });

    test('a preview of an unknown version is refused', () {
      expect(
          () => InvitationPreview.fromJson({
                'v': 2,
                'inviterName': 'Alice',
                'message': '',
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
        contactId: 'c1',
        code: '012345',
        expiresAt: DateTime.utc(2026, 10, 6),
        inviterName: 'Alice',
        message: 'hi',
        contentKey: 'a2V5',
        status: SentInvitationStatus.accepted,
        acceptedBy: '@bob'.toAtsign(),
      );

      final back =
          SentInvitation.fromJson(jsonDecode(jsonEncode(sent.toJson())));

      expect(back.toJson(), sent.toJson());
      expect(back.code, '012345', reason: 'a code keeps its leading zero');
    });

    test('ReceivedInvitation', () {
      final received = ReceivedInvitation(
        inviter: '@alice'.toAtsign(),
        inviterName: 'Alice',
        message: 'hi',
        expiresAt: DateTime.utc(2026, 10, 6),
        content:
            const SealedInvitationContent(nonce: 'bg==', ciphertext: 'Yw=='),
        status: ReceivedInvitationStatus.connected,
        plaintext: 'the recipe',
      );

      expect(
          ReceivedInvitation.fromJson(jsonDecode(jsonEncode(received.toJson())))
              .toJson(),
          received.toJson());
    });
  });
}
