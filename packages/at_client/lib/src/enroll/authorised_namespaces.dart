import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_commons/at_commons.dart' show EnrollmentConstants;

/// The namespaces [atClient] holds data in, and so holds a key for.
///
/// An APKAM client is told by its own enrollment record, all the atServer
/// returns without `__manage`, while a legacy PKAM client has no enrollment
/// and names exactly one — its `preference.namespace`, which is also what a
/// grant of `*` stands for, `__manage` being skipped either way.
///
/// Throws when the enrollment record cannot be read; the caller decides what
/// an unknown answer means for it.
Future<Set<String>> authorisedNamespacesOf(AtClient atClient) async {
  final own = atClient.getPreferences()?.namespace;
  final ownNamespace = (own == null || own.isEmpty) ? const <String>{} : {own};
  final enrollmentId = atClient.enrollmentId;
  if (isAtSignCredential(enrollmentId)) return ownNamespace;

  final mine = (await atClient.enrollmentService!.fetchEnrollmentRequests())
      .where((e) => e.enrollmentId == enrollmentId);
  final granted = {
    for (final enrollment in mine) ...?enrollment.namespace?.keys
  };
  return {
    ...granted.where(isSeedableNamespace),
    if (granted.contains(EnrollmentConstants.allNamespaces)) ...ownNamespace,
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
