import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// `notify:multi`: one value notified to many recipients by one request, in a
/// grammar an atServer that predates it refuses.
void main() {
  // FROZEN: the wire form every atServer implementation parses. An intended
  // change edits this literal, and that edit is the review.
  const built =
      'notify:multi:update:ttln:900000:isEncrypted:true:appMetadata:eyJwcm92aWRlcklkIjoiYXQvc3ltbWV0cmljL0FFUy9HQ00vZ3JvdXAiLCJja0tpZCI6ImFiY2QiLCJpdiI6ImFYWT0iLCJucyI6ImNoYXQubXlhcHAiLCJja05zIjoiY2hhdC5teWFwcCJ9:@bob,@sitaram:msg.chat.myapp@alice:CIPHERTEXT';

  final notifyMulti = RegExp(VerbSyntax.notifyMulti);

  NotifyMultiVerbBuilder builder() => NotifyMultiVerbBuilder()
    ..atKey = (AtKey()
      ..key = 'msg'
      ..namespace = 'chat.myapp'
      ..sharedBy = '@alice'
      ..metadata = (Metadata()
        ..isEncrypted = true
        ..appMetadata = AppMetadata(
            providerId: 'at/symmetric/AES/GCM/group',
            additional: {
              'ckKid': 'abcd',
              'iv': 'aXY=',
              'ns': 'chat.myapp',
              'ckNs': 'chat.myapp'
            })))
    ..recipients = ['@bob', 'sitaram']
    ..operation = OperationEnum.update
    ..ttln = 900000
    ..value = 'CIPHERTEXT';

  test('the builder writes the frozen wire form', () {
    expect(builder().buildCommand(), '$built\n',
        reason: 'every recipient written with its @, and the key with its '
            'namespace');
  });

  test('the grammar parses what the builder writes', () {
    final m = notifyMulti.firstMatch(built)!;
    expect(m.namedGroup('operation'), 'update');
    expect(m.namedGroup('ttln'), '900000');
    expect(m.namedGroup('isEncrypted'), 'true');
    expect(m.namedGroup('forAtSign'), '@bob,@sitaram');
    expect(m.namedGroup('atKey'), 'msg.chat.myapp');
    expect(m.namedGroup('atSign'), 'alice');
    expect(m.namedGroup('value'), 'CIPHERTEXT');
  });

  group('a malformed command is refused, never misrouted', () {
    test('a malformed metadata field is not taken for a recipient', () {
      for (final command in [
        'notify:multi:update:ttl:abc:isEncrypted:true:@bob,@sitaram:msg.chat.myapp@alice:CIPHERTEXT',
        'notify:multi:update:isEncrypted:maybe:@bob,@sitaram:msg.chat.myapp@alice:CIPHERTEXT',
        // NOTE: only the @ on each recipient refuses this one; the required
        // sender alone would read it as recipient ttl, key abc, sender evil.
        'notify:multi:update:ttl:abc@evil:isEncrypted:true:@bob,@sitaram:msg.chat.myapp@alice:CIPHERTEXT',
      ]) {
        expect(notifyMulti.hasMatch(command), isFalse, reason: command);
      }
    });

    test('a recipient without its @ is refused', () {
      expect(
          notifyMulti.hasMatch(
              'notify:multi:isEncrypted:true:bob,@sitaram:msg.chat.myapp@alice:x'),
          isFalse);
    });

    test('a command naming no sender is refused', () {
      expect(
          notifyMulti.hasMatch(
              'notify:multi:isEncrypted:true:@bob,@sitaram:msg.chat.myapp:x'),
          isFalse);
    });
  });

  test("an atServer that predates the verb refuses it", () {
    // What an older atServer would try: plain notify takes every notify:
    // command it does not exclude, and notify:all's grammar is the one that
    // misreads metadata as recipients.
    expect(RegExp(VerbSyntax.notify).hasMatch(built), isFalse);
    expect(RegExp(VerbSyntax.notifyAll).hasMatch(built), isFalse);
    expect(
        RegExp(VerbSyntax.notifyAll).hasMatch(
            'notify:all:update:ttl:60000:@bob,@sitaram:msg.chat.myapp@alice:x'),
        isTrue,
        reason: 'the control: the notify:all grammar does match its own form');
  });

  test('the builder refuses no recipients, or no sender', () {
    expect(() => (builder()..recipients = []).buildCommand(),
        throwsArgumentError);
    expect(() => (builder()..atKey.sharedBy = null).buildCommand(),
        throwsArgumentError);
  });
}
