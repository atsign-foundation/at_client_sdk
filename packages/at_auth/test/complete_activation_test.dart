import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// A connection that records every verb it is asked to send.
class _RecordingLookUp extends Fake implements AtLookUp {
  final sent = <String>[];

  /// Makes every `update` verb throw this once it is recorded.
  Object? updateError;

  /// Makes every `delete` verb throw this once it is recorded.
  Object? deleteError;

  @override
  Future<String?> executeVerb(VerbBuilder builder, {bool sync = false}) async {
    sent.add(builder.buildCommand());
    if (updateError case final e? when builder is UpdateVerbBuilder) throw e;
    if (deleteError case final e? when builder is DeleteVerbBuilder) throw e;
    return 'data:1';
  }
}

void main() {
  group('completeActivationOf', () {
    test(
        'A completion publishes the encryption public key with ttr -1, then '
        'deletes the CRAM secret', () async {
      final lookUp = _RecordingLookUp();
      await completeActivationOf(
          atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: 'cHVi');
      expect(lookUp.sent, [
        'update:ttr:-1:isEncrypted:false:public:publickey@alice cHVi\n',
        'delete:privatekey:at_secret\n',
      ]);
    });

    test(
        'A completion with no encryption public key deletes only the CRAM '
        'secret', () async {
      final lookUp = _RecordingLookUp();
      await completeActivationOf(
          atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: null);
      expect(lookUp.sent, ['delete:privatekey:at_secret\n']);
    });

    test('A failed publish keeps the CRAM secret and propagates', () async {
      final error = StateError('publish failed');
      final lookUp = _RecordingLookUp()..updateError = error;
      await expectLater(
          completeActivationOf(
              atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: 'cHVi'),
          throwsA(same(error)));
      expect(lookUp.sent,
          ['update:ttr:-1:isEncrypted:false:public:publickey@alice cHVi\n']);
    });

    for (final (name, value) in [
      ('a line feed', 'cHVi\nZGVs'),
      ('a carriage return', 'cHVi\rZGVs'),
    ]) {
      test(
          'An encryption public key holding $name is refused before any '
          'command', () async {
        final lookUp = _RecordingLookUp();
        await expectLater(
            completeActivationOf(
                atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: value),
            throwsArgumentError);
        expect(lookUp.sent, isEmpty);
      });
    }

    test('A CRAM secret the atServer reports as not found counts as deleted',
        () async {
      final lookUp = _RecordingLookUp()
        ..deleteError = AtLookUpException('AT0015', 'key not found');
      await completeActivationOf(
          atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: 'cHVi');
      expect(lookUp.sent, hasLength(2));
    });

    test('A CRAM secret delete refused for another reason propagates',
        () async {
      final refusal = AtLookUpException('AT0003', 'unauthorized');
      final lookUp = _RecordingLookUp()..deleteError = refusal;
      await expectLater(
          completeActivationOf(
              atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: null),
          throwsA(same(refusal)));
    });
  });

  group('publishEncryptionPublicKeyOf', () {
    test(
        'A publish sends the encryption public key with ttr -1 and does not '
        'delete the CRAM secret', () async {
      final lookUp = _RecordingLookUp()
        ..deleteError = StateError('the CRAM secret delete was sent');
      await publishEncryptionPublicKeyOf(
          atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: 'cHVi');
      expect(lookUp.sent,
          ['update:ttr:-1:isEncrypted:false:public:publickey@alice cHVi\n']);
    });

    for (final (name, value) in [
      ('a line feed', 'cHVi\nZGVs'),
      ('a carriage return', 'cHVi\rZGVs'),
    ]) {
      test(
          'An encryption public key holding $name is refused before any '
          'command', () async {
        final lookUp = _RecordingLookUp();
        await expectLater(
            publishEncryptionPublicKeyOf(
                atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: value),
            throwsArgumentError);
        expect(lookUp.sent, isEmpty);
      });
    }
  });
}
