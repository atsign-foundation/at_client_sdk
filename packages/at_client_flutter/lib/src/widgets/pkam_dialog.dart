import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';

class PkamDialog extends StatelessWidget {
  PkamDialog({super.key, required this.request});
  final AuthService auth = AuthService();
  final AtAuthRequest request;

  static Future<AtAuthResponse?> show(BuildContext context, {
    required AtAuthRequest request,
    }) async {
    return showDialog<AtAuthResponse>(
      context: context,
      builder: (context) => PkamDialog(request: request),
    );
  }

  @override
  Widget build(BuildContext context) {
    auth.authenticate(request).then((value) {
      print('Authentication completed with response: $value');
      Navigator.of(context).pop(value);
    });
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder(
          stream: auth.progressStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LoadingDialog(title: "Onboarding ", description: "Validating your atKeys...");
            }
            final progress = snapshot.data as ProgressEvent;
            if (progress.type == ProgressEventType.success) {
              return const Text("Authentication Successful");
            } else if (progress.type == ProgressEventType.error) {
              return Text("Error: ${progress.msg}");
            } else {
              return Text("Progress: ${progress.msg}");
            }
          },
        ),
      ),
    );
  }
}