import 'package:at_commons/at_commons.dart' hide StringBuffer;
import 'package:test/test.dart';

/// Throws an [AtEncryptionException] whose message contains [fragment].
///
/// The message is what tells one guard from another: two guards that raise the
/// same exception type are indistinguishable to a bare `isA`.
Matcher throwsEncryption(String fragment) =>
    throwsA(isA<AtEncryptionException>()
        .having((e) => e.message, 'message', contains(fragment)));

/// Throws an [AtDecryptionException] whose message contains [fragment].
Matcher throwsDecryption(String fragment) =>
    throwsA(isA<AtDecryptionException>()
        .having((e) => e.message, 'message', contains(fragment)));
