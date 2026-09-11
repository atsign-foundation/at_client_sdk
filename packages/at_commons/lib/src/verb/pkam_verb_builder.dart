import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart' show EnrollmentConstants;

class PkamVerbBuilder implements VerbBuilder {
  /// The enrollment authenticating. [EnrollmentConstants.primaryEnrollmentId]
  /// is kept off the wire: a released atServer knows the atSign's own
  /// credential only by the absence of an id.
  String? enrollmentlId;

  /// The algorithm the challenge signature was made with — the APKAM
  /// *authentication* key's, which is the only key this verb involves.
  ///
  /// Not the algorithm the enrollment signs documents with: that key is its
  /// own, advertised in `_apsk`, and from rollout 1 onward it is deliberately
  /// a different algorithm. The two share a field name and nothing else.
  String? signingAlgo;

  String? hashingAlgo;

  /// base64encoded signed challenge
  late String signature;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('pkam');
    if (signingAlgo != null && signingAlgo!.isNotEmpty) {
      serverCommandBuffer.write(':signingAlgo:$signingAlgo');
    }
    if (hashingAlgo != null && hashingAlgo!.isNotEmpty) {
      serverCommandBuffer.write(':hashingAlgo:$hashingAlgo');
    }
    if (enrollmentlId != null &&
        enrollmentlId!.isNotEmpty &&
        enrollmentlId != EnrollmentConstants.primaryEnrollmentId) {
      serverCommandBuffer.write(':enrollmentId:$enrollmentlId');
    }
    return (serverCommandBuffer..write(':$signature\n')).toString();
  }

  @override
  bool checkParams() {
    return signature.isNotEmpty;
  }
}
