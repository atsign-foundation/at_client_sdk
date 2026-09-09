import 'package:at_lookup/at_lookup.dart' show SecondaryAddressFinder;

/// The process-wide source [processSecondaryAddressFinder] reads, or null
/// when nothing has registered one.
SecondaryAddressFinder? Function()? _source;

/// Registers where [processSecondaryAddressFinder] looks. Later
/// registrations replace earlier ones.
void registerSecondaryAddressFinderSource(
    SecondaryAddressFinder? Function() source) {
  _source = source;
}

/// The process's atDirectory lookup, or null when none is available.
///
/// The source is called per lookup rather than captured, so a finder
/// registered after the caller was built is still found.
SecondaryAddressFinder? processSecondaryAddressFinder() => _source?.call();
