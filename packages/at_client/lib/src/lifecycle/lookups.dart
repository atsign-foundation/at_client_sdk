import 'package:at_lookup/at_lookup_io.dart';

/// The connections a client opens when its application supplied no
/// [AtLookUpFactory]: TLS on TCP with the defaults.
///
/// The one place in this package that names the TLS transport; everything
/// else takes the factory it is handed or asks here.
AtLookUpFactory defaultLookUps() => secureSocketLookUps();
