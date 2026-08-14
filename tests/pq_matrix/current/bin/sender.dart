import 'package:pq_matrix_current/arm.dart'
    show attachWithKeyfile, currentPreference;
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
      stages: const {'now', 'rollout1', 'rollout2'},
      preferenceFor: currentPreference,
      attach: attachWithKeyfile,
    );
