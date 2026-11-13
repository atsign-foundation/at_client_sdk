import 'package:at_client/at_client_io.dart';

/// The atDirectory [preference] names, asked over TLS, for a sample run by
/// hand against the environment it names.
SecondaryAddressFinder atDirectoryOf(AtClientPreference preference) =>
    CacheableSecondaryAddressFinder(preference.rootDomain, preference.rootPort);
