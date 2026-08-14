import 'package:pq_matrix_published/arm.dart' show publishedPreference;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart';

/// The control arm's sender: at_client 3.14.0, exactly as pub.dev ships it.
Future<void> main(List<String> args) => runArm(
      args,
      role: Role.sender,
      stages: const {'published'},
      preferenceFor: publishedPreference,
    );
