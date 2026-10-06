/// What the upgrade check asks a client to write and to report, written once
/// so the same steps run on every released at_client and on this tree.
///
/// No single process can hold two versions of at_client, so a released arm
/// runs `bin/seed.dart` under its own resolution and this tree's check links
/// the library directly.
library;

export 'package:pq_matrix_scenario/connect.dart'
    show ClientSpec, attachWithoutKeySource, connect;

export 'src/catalogue.dart';
export 'src/lifecycle.dart';
export 'src/preference.dart';
export 'src/seed.dart';
export 'src/snapshot.dart';
