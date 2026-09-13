import 'package:at_chops/at_chops.dart';

/// One PKAM keypair per (atSign, enrollmentId), generated once per test file
/// and reused by every fixture that asks for the same pair.
///
/// An RSA keypair costs roughly 140ms — about forty times what building and
/// stopping a whole client costs — and the fixtures here were generating one
/// per client. A file building two clients in each of forty tests spent
/// eleven seconds on keys whose values nothing asserts.
///
/// ⛔ Keyed by the PAIR, never by the atSign alone. Two enrollments of one
/// atSign are two principals, and several tests are differentials that move a
/// key from one to the other; handed a single keypair they would compare a
/// record against itself and pass having moved nothing. `pq_signing_chain_test`
/// says exactly that on its assertions, and caught it when this cache was
/// first keyed on the atSign.
///
/// A test that needs a genuinely fresh keypair — one whose value it asserts,
/// or a second key for the same principal — calls `AtChopsUtil` directly.
AtPkamKeyPair pkamKeyPairFor(String atSign, String? enrollmentId) =>
    _pkamKeyPairs.putIfAbsent(
        '$atSign/$enrollmentId', AtChopsUtil.generateAtPkamKeyPair);

final _pkamKeyPairs = <String, AtPkamKeyPair>{};
