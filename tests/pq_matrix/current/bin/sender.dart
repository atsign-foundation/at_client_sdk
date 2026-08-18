import 'package:pq_matrix_current/arm.dart'
    show attachWithKeyfile, currentPreference;
import 'package:pq_matrix_current/envelope_exchange.dart'
    show signEnvelopeForPeer;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart';

/// This tree's sender, at whichever stage of the auth/signing split it is told.
///
/// It does not serve `published`, and says so rather than approximating it —
/// a build simulating the released one exercises the stage logic and nothing
/// else, which is the limitation the sibling `published/` package exists to
/// remove.
Future<void> main(List<String> args) => runArm(
      args,
      role: Role.sender,
      stages: const {'legacy', 'pqReady', 'pqActive'},
      preferenceFor: currentPreference,
      attach: attachWithKeyfile,
      // The envelope grid rides the cells this arm is both halves of. It is
      // passed here rather than written into the shared scenario because the
      // published arm cannot compile it, and it is a step rather than a call
      // in this file because its ordering constraint — before the notification
      // — belongs with the sequence it is part of.
      step: signEnvelopeForPeer,
    );
