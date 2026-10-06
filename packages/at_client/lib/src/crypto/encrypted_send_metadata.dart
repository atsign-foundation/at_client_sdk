import 'package:at_commons/at_commons.dart' show Metadata;

/// The metadata a put or notification the SDK encrypts goes out with: the
/// fields its caller decides, taken from [given], and none of the fields an
/// encryption or the atServer produces.
///
/// Built fresh for every such send, so nothing an earlier send left on a reused
/// key (its IV, the provider it was sealed under, the shared-key copy it
/// cited) can carry into the next one. A field added to [Metadata] later is
/// left out until `encrypted_send_metadata_test.dart` classifies it.
Metadata metadataForEncryptedSend(Metadata given) => Metadata()
  ..ttl = given.ttl
  ..ttb = given.ttb
  ..ttr = given.ttr
  ..ccd = given.ccd
  ..isPublic = given.isPublic
  ..isHidden = given.isHidden
  ..namespaceAware = given.namespaceAware
  ..isBinary = given.isBinary
  ..immutable = given.immutable;
