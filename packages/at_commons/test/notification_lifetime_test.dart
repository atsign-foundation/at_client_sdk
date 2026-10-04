import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// A notification's own expiry (`eAtn`) and whether any atServer persists it
/// (`eph`).
void main() {
  // FROZEN: the wire form every atServer implementation parses. An intended
  // change edits this literal, and that edit is the review.
  const plain =
      'notify:id:n1:update:notifier:SYSTEM:eAtn:2026-10-04T10:45:00.721000Z:eph:isEncrypted:true:@bob:msg.chat.myapp@alice:CIPHERTEXT';

  final expiresAt = DateTime.utc(2026, 10, 4, 10, 45, 0, 721);

  NotifyVerbBuilder plainBuilder() => NotifyVerbBuilder()
    ..id = 'n1'
    ..atKey = (AtKey.fromString('@bob:msg.chat.myapp@alice')
      ..metadata = (Metadata()..isEncrypted = true))
    ..operation = OperationEnum.update
    ..notificationExpiresAt = expiresAt
    ..ephemeral = true
    ..value = 'CIPHERTEXT'
    ..useAtKeyToString = true;

  test('the builder writes the frozen wire form', () {
    expect(plainBuilder().buildCommand(), '$plain\n');
  });

  test('the grammar parses it', () {
    final m = RegExp(VerbSyntax.notify).firstMatch(plain)!;
    expect(m.namedGroup(AtConstants.notificationExpiresAt),
        '2026-10-04T10:45:00.721000Z');
    expect(m.namedGroup(AtConstants.ephemeral), 'eph');
    expect(m.namedGroup('forAtSign'), 'bob');
    expect(m.namedGroup('value'), 'CIPHERTEXT');
  });

  test('a notify without them parses as before, with neither set', () {
    final m = RegExp(VerbSyntax.notify).firstMatch(
        'notify:id:n2:update:notifier:SYSTEM:ttln:900000:isEncrypted:true:@bob:msg.chat.myapp@alice:x')!;
    expect(m.namedGroup(AtConstants.ttlNotification), '900000');
    expect(m.namedGroup(AtConstants.notificationExpiresAt), isNull);
    expect(m.namedGroup(AtConstants.ephemeral), isNull);
  });

  test('a malformed eAtn is refused, not read as something else', () {
    expect(
        RegExp(VerbSyntax.notify).hasMatch(
            'notify:id:n3:update:eAtn:tomorrow:isEncrypted:true:@bob:msg.chat.myapp@alice:x'),
        isFalse);
  });

  test('eph is a bare flag: one carrying a value is refused', () {
    expect(
        RegExp(VerbSyntax.notify).hasMatch(
            'notify:id:n4:update:eph:true:isEncrypted:true:@bob:msg.chat.myapp@alice:x'),
        isFalse);
    expect(
        RegExp(VerbSyntax.notify).hasMatch(
            'notify:id:n4:update:eph:isEncrypted:true:@bob:msg.chat.myapp@alice:x'),
        isTrue,
        reason: 'the control: the same command with a bare eph parses');
  });

  group('the builders refuse what the atServer refuses', () {
    test('ttln and eAtn together', () {
      expect(() => (plainBuilder()..ttln = 60000).buildCommand(),
          throwsArgumentError);
    });

    test('eph with a ttr or ccd', () {
      expect(
          () => (plainBuilder()..atKey.metadata.ttr = 60000).buildCommand(),
          throwsArgumentError);
      expect(() => (plainBuilder()..atKey.metadata.ccd = true).buildCommand(),
          throwsArgumentError);
    });

    test('the control: a ttr without eph still builds on plain notify', () {
      expect(
          (plainBuilder()
                ..ephemeral = false
                ..atKey.metadata.ttr = 60000)
              .buildCommand(),
          contains(':ttr:60000'));
    });

    test('eph on a delete, since a delete removes a cached record', () {
      expect(
          () => (plainBuilder()..operation = OperationEnum.delete)
              .buildCommand(),
          throwsArgumentError);
    });

    test('the control: a delete without eph still builds', () {
      expect(
          (plainBuilder()
                ..ephemeral = false
                ..operation = OperationEnum.delete)
              .buildCommand(),
          startsWith('notify:id:n1:delete:'));
    });
  });
}
