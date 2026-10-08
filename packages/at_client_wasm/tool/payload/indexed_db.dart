import 'package:at_client_wasm/at_client_wasm.dart';

import 'common.dart';

Future<void> main() =>
    exercise(IndexedDbAtClientStorage(atSign: '@payload', enrollmentId: 'e1'));
