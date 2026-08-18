import 'package:pq_matrix_current/arm.dart'
    show attachWithKeyfile, currentPreference;
import 'package:pq_matrix_current/envelope_exchange.dart'
    show verifyPeerEnvelope;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart';

/// This tree's receiver, at whichever stage of the auth/signing split it is
/// told.
Future<void> main(List<String> args) => runArm(
      args,
      role: Role.receiver,
      stages: const {'legacy', 'pqReady', 'pqActive'},
      preferenceFor: currentPreference,
      attach: attachWithKeyfile,
      // Verifies the peer's envelope after the data-path reads, so a
      // verification failure cannot be read as the data path breaking. A cell
      // whose sender was the published arm leaves no envelope, and the step
      // reports that rather than throwing — the driver knows which cells are
      // envelope cells.
      step: verifyPeerEnvelope,
    );
