import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_commons/at_commons.dart' show AtKey, EnrollmentConstants;

/// The namespaces [atClient] holds data in, and so holds a key for.
///
/// An APKAM client is told by its own enrollment record, all the atServer
/// returns without `__manage`, while a legacy PKAM client has no enrollment
/// and names exactly one — [ownNamespace], its `preference.namespace`, which
/// is also what a grant of `*` stands for, `__manage` being skipped either way.
///
/// Throws when the enrollment record cannot be read; the caller decides what
/// an unknown answer means for it.
Future<Set<String>> authorisedNamespacesOf(AtClient atClient,
        {required String? ownNamespace}) async =>
    authorisedNamespacesIn(await ownGrantsOf(atClient),
        ownNamespace: ownNamespace);

/// The grants [atClient]'s own enrollment record holds, or null for the
/// atSign's own credential, which no grant limits.
///
/// Throws when the enrollment record cannot be read.
Future<Map<String, dynamic>?> ownGrantsOf(AtClient atClient) async {
  final enrollmentId = atClient.enrollmentId;
  if (isAtSignCredential(enrollmentId)) return null;
  final mine = (await atClient.enrollmentService!.fetchEnrollmentRequests())
      .where((e) => e.enrollmentId == enrollmentId);
  return {for (final enrollment in mine) ...?enrollment.namespace};
}

/// The namespaces [grants] hold data in, as [authorisedNamespacesOf] reads
/// them: [ownNamespace] alone for null [grants], the atSign's own credential.
Set<String> authorisedNamespacesIn(Map<String, dynamic>? grants,
    {required String? ownNamespace}) {
  final own = (ownNamespace == null || ownNamespace.isEmpty)
      ? const <String>{}
      : {ownNamespace};
  if (grants == null) return own;
  return {
    ...grants.keys.where(isSeedableNamespace),
    if (grants.containsKey(EnrollmentConstants.allNamespaces)) ...own,
  };
}

/// Whether [namespace] can hold data, and so a namespace key, of its own.
///
/// `*` and `__manage` are grants over *other* namespaces rather than
/// namespaces data lives in; the answer comes from the argument alone.
bool isSeedableNamespace(String namespace) =>
    namespace != EnrollmentConstants.allNamespaces &&
    namespace != '__manage' &&
    namespace.isNotEmpty;

/// The access [grants] give to [namespace], or null when they give none.
///
/// Resolved as the atServer resolves a key, which reads its namespace as the
/// last dot segment: a grant on that segment wins, then the first grant on
/// [namespace] itself or on a namespace above it, and `*` answers only for a
/// namespace no such grant covers.
String? accessIn(Map<String, dynamic> grants, String namespace) {
  final lastSegment = namespace.substring(namespace.lastIndexOf('.') + 1);
  final onLastSegment = grants[lastSegment];
  if (lastSegment != EnrollmentConstants.allNamespaces &&
      onLastSegment != null) {
    return '$onLastSegment';
  }
  for (final MapEntry(key: granted, value: access) in grants.entries) {
    if (granted == EnrollmentConstants.allNamespaces) continue;
    if (granted == namespace || namespace.endsWith('.$granted')) {
      return '$access';
    }
  }
  final all = grants[EnrollmentConstants.allNamespaces];
  return all == null ? null : '$all';
}

/// The grant in [grants] that covers [atKey], the access it gives and the
/// key's namespace, or null when no grant gives it any.
///
/// Decided as the atServer decides it for a key. A grant on the key's
/// namespace, its last dot segment, wins. Otherwise the first grant the key's
/// name ends with, after a dot, covers it: `cmp.rotation` covers
/// `x.cmp.rotation@bob`, but not `cmp.rotation@bob`, whose name is `cmp` in
/// `rotation`. `*` answers only for a key no grant covers, and alone for a key
/// that does not parse. Unlike [accessIn], a key's name is not its namespace.
({String grant, String access, String? namespace})? grantCovering(
    Map<String, dynamic> grants, String atKey) {
  String? namespace;
  var keyWithNamespace = '';
  try {
    final parsed = AtKey.fromString(atKey);
    namespace = parsed.namespace;
    if (namespace != null && namespace.isNotEmpty) {
      keyWithNamespace = '${parsed.key}.$namespace';
    }
  } catch (_) {
    // NOTE: AtKey.fromString raises Errors as well as Exceptions.
    namespace = null;
  }
  String? granted;
  if (namespace != null && namespace.isNotEmpty) {
    for (final grant in grants.keys) {
      if ('.$namespace'.endsWith('.$grant')) {
        granted = grant;
        break;
      }
    }
  }
  if (granted == null && keyWithNamespace.isNotEmpty) {
    for (final grant in grants.keys) {
      if (keyWithNamespace.endsWith('.$grant')) {
        granted = grant;
        break;
      }
    }
  }
  if (granted == null &&
      grants.containsKey(EnrollmentConstants.allNamespaces)) {
    granted = EnrollmentConstants.allNamespaces;
  }
  final access = granted == null ? null : grants[granted];
  return access == null
      ? null
      : (grant: granted!, access: '$access', namespace: namespace);
}

/// Whether a client granted [own] may write to [namespace].
///
/// A null [own] is a client with no recorded limit, and may write anywhere.
bool mayWriteIn(Map<String, dynamic>? own, String namespace) =>
    own == null || (accessIn(own, namespace)?.contains('w') ?? false);
