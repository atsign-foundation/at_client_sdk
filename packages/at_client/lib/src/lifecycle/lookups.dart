import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_commons/at_commons.dart' show SecureSocketConfig;
import 'package:at_lookup/at_lookup_io.dart';

/// The connections a client opens when its application supplied no
/// [AtLookUpFactory]: TLS on TCP, configured from the preference's transport
/// fields for as long as those are read.
AtLookUpFactory defaultLookUps(AtClientPreference preference) =>
    secureSocketLookUps(
        config: SecureSocketConfig()
          // ignore: deprecated_member_use_from_same_package
          ..decryptPackets = preference.decryptPackets
          // ignore: deprecated_member_use_from_same_package
          ..pathToCerts = preference.pathToCerts
          // ignore: deprecated_member_use_from_same_package
          ..tlsKeysSavePath = preference.tlsKeysSavePath);
