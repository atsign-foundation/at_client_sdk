import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show AtKeysPassphraseEnvelopeCodec, printableEnrollmentId;
import 'package:at_client/at_client.dart'
    show
        AtDecryptionException,
        AtEnrollmentPendingException,
        AtKeysUnusableCause,
        AtKeysUnusableException;
import 'package:chalkdart/chalk.dart';

/// The line a command-line program ends every keys problem with.
const String keysProblemFooter = 'Need help? support@atsign.com. Never send '
    'anyone your .atKeys file, support included.';

/// The next steps for keys absent from this machine when whether [atSign]
/// has been activated is not known.
List<String> eitherKeysHint(String atSign) => [
      '  Not activated yet?             at_activate onboard -a $atSign',
      '  Activated on another machine?  Run this command there, or enroll '
          'this machine first.',
    ];

/// Writes [e] to stderr as one message, for a program whose atSign and
/// keyfile are given with -a, -k and -P: what is wrong and where, the next
/// step, and [keysProblemFooter]. [absentHint] are the lines that follow the
/// first when the keys are absent.
void reportKeysProblem(AtKeysUnusableException e,
    {required List<String> absentHint}) {
  final lines = switch (e.cause) {
    AtKeysUnusableCause.absent => [
        'No keys for ${e.atSign} at ${e.source}.',
        ...absentHint,
      ],
    AtKeysUnusableCause.unreadable
        when e.error is AtDecryptionException &&
            _isPassphraseProtected(e.source) =>
      [
        'Could not read the keys for ${e.atSign} at ${e.source}: the '
            'passphrase is wrong or missing.',
        '  If the keyfile has a passphrase, pass it with -P.',
      ],
    AtKeysUnusableCause.anotherAtsign => ['${e.message} Check -a and -k.'],
    AtKeysUnusableCause.pendingEnrollment
        when e is AtEnrollmentPendingException && !_isSeveralMatching(e) =>
      [_waitForApproval(e)],
    _ => [e.message],
  };
  stderr.writeln();
  stderr.writeln(chalk.brightRed(lines.first));
  for (final line in lines.skip(1)) {
    stderr.writeln(line);
  }
  stderr.writeln(keysProblemFooter);
}

/// Whether [e] is `AtEnrollmentPendingException.several`'s refusal of
/// several pending enrollments that match, which waiting cannot resolve.
bool _isSeveralMatching(AtEnrollmentPendingException e) =>
    e.message ==
    AtEnrollmentPendingException.several(e.atSign, e.pendingEnrollmentIds)
        .message;

/// The line for keys holding only the pending enrollment requests [e] names:
/// wait for approval, then run the command again.
String _waitForApproval(AtEnrollmentPendingException e) {
  final ids = e.pendingEnrollmentIds;
  final one = ids.length == 1;
  return 'This keyfile holds only '
      '${one ? 'a pending enrollment request' : 'pending enrollment requests'} '
      'for ${e.atSign} (${one ? 'id' : 'ids'} '
      '${ids.map(printableEnrollmentId).join(', ')}). Wait for '
      '${one ? 'it' : 'them'} to be approved, then run this command again.';
}

/// Whether the keyfile at [path] is a passphrase envelope.
bool _isPassphraseProtected(String? path) {
  if (path == null) return false;
  try {
    final json = jsonDecode(File(path).readAsStringSync());
    return json is Map<String, dynamic> &&
        const AtKeysPassphraseEnvelopeCodec().isEnvelope(json);
  } catch (_) {
    return false;
  }
}
