import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_lookup/at_lookup_io.dart';

SecureSocketConfig _defaultConfig(AtClientPreference preference) =>
    SecureSocketConfig()
      // ignore: deprecated_member_use_from_same_package
      ..decryptPackets = preference.decryptPackets
      // ignore: deprecated_member_use_from_same_package
      ..pathToCerts = preference.pathToCerts
      // ignore: deprecated_member_use_from_same_package
      ..tlsKeysSavePath = preference.tlsKeysSavePath;

/// The connections a client opens when its application supplied no
/// [AtLookUpFactory]: TLS on TCP, configured from the preference's transport
/// fields for as long as those are read, and the TLS defaults with no
/// preference in reach.
///
/// The one place in this package that names the TLS transport; everything
/// else takes the factory it is handed or asks here.
AtLookUpFactory defaultLookUps([AtClientPreference? preference]) =>
    preference == null
        ? secureSocketLookUps()
        : secureSocketLookUps(config: _defaultConfig(preference));
