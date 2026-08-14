import 'package:pq_matrix_current/arm.dart'
    show attachWithKeyfile, currentPreference;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart';

/// This tree's receiver, at whichever stage of the auth/signing split it is
/// told.
Future<void> main(List<String> args) => runArm(
      args,
      role: Role.receiver,
      stages: const {'now', 'rollout1', 'rollout2'},
      preferenceFor: currentPreference,
      attach: attachWithKeyfile,
    );
