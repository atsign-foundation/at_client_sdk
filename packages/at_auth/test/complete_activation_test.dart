import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// A connection that records every verb it is asked to send.
class _RecordingLookUp extends Fake implements AtLookUp {
  final sent = <String>[];

  @override
  Future<String?> executeVerb(VerbBuilder builder, {bool sync = false}) async {
    sent.add(builder.buildCommand());
    return 'data:1';
  }
}

void main() {
  group('completeActivationOf', () {
    test(
        'publishes the encryption public key with ttr -1, then deletes the '
        'CRAM secret', () async {
      final lookUp = _RecordingLookUp();
      await completeActivationOf(
          atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: 'cHVi');
      expect(lookUp.sent, [
        'update:ttr:-1:isEncrypted:false:public:publickey@alice cHVi\n',
        'delete:privatekey:at_secret\n',
      ]);
    });

    test('with no encryption public key, deletes the CRAM secret only',
        () async {
      final lookUp = _RecordingLookUp();
      await completeActivationOf(
          atLookUp: lookUp, atSign: '@alice', encryptionPublicKey: null);
      expect(lookUp.sent, ['delete:privatekey:at_secret\n']);
    });
  });
}
