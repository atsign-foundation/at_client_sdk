import 'dart:io';

import 'package:at_client/at_client.dart'
    show
        AtEnrollmentPendingException,
        AtKeysPassphraseException,
        AtKeysUnusableCause,
        AtKeysUnusableException;
import 'package:at_commons/at_commons.dart' show clipForMessage;
import 'package:chalkdart/chalk.dart';

/// The line a command-line program ends every keys problem with.
const String keysProblemFooter = 'Need help? support@atsign.com. Never send '
    'anyone your .atKeys file, support included.';

/// The next steps for keys absent from this machine when whether [atSign]
/// has been activated is not known; [root] is the atDirectory to activate it
/// in, as `-r` takes it.
List<String> eitherKeysHint(String atSign, String root) => [
      '  Not activated yet?             at_activate onboard -a $atSign -r '
          '$root',
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
    // NOTE: a refused passphrase only; other refusals keep their reason.
    AtKeysUnusableCause.unreadable when e.error is AtKeysPassphraseException =>
      [
        'Could not read the keys for ${e.atSign} at ${e.source}: the '
            'passphrase is wrong or missing.',
        '  If the keyfile has a passphrase, pass it with -P.',
      ],
    AtKeysUnusableCause.anotherAtsign => ['${e.message} Check -a and -k.'],
    AtKeysUnusableCause.pendingEnrollment
        when e is AtEnrollmentPendingException =>
      _waitForApproval(e),
    AtKeysUnusableCause.noCredential when e.source != null => [
        'The keyfile at ${e.source} holds no credential for ${e.atSign}: its '
            'enrollment was denied, cancelled or expired, or never completed. '
            'Enroll this machine again.',
      ],
    _ => [e.message],
  };
  stderr.writeln();
  stderr.writeln(chalk.brightRed(lines.first));
  for (final line in lines.skip(1)) {
    stderr.writeln(line);
  }
  stderr.writeln(keysProblemFooter);
}

/// The lines for keys holding only the pending enrollment requests [e]
/// names: once one is approved, the enroll command that made it finishes it,
/// and `at_activate cancel` gives it up.
List<String> _waitForApproval(AtEnrollmentPendingException e) {
  final ids = e.pendingEnrollmentIds;
  final keyfile =
      e.source == null ? 'This keyfile' : 'The keyfile at ${e.source}';
  final cancel =
      'at_activate cancel -a ${e.atSign} -k ${e.source ?? '<keyfile>'}';
  return ids.length == 1
      ? [
          '$keyfile holds only a pending enrollment request for '
              '${e.atSign} (id ${clipForMessage(ids.single)}). Once it is '
              'approved, run the same at_activate enroll command again to '
              'finish it.',
          '  To give it up instead: $cancel',
        ]
      : [
          '$keyfile holds only pending enrollment requests for '
              '${e.atSign} (ids ${ids.map(clipForMessage).join(', ')}). Once '
              'one is approved, run the at_activate enroll command that made '
              'it again to finish it.',
          '  To give them up instead, one each time: $cancel',
        ];
}
