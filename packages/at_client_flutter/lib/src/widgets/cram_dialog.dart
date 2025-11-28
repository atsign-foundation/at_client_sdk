import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';

class CramDialog extends StatelessWidget {
  CramDialog({super.key, required this.request, required this.cramKey});

  final AtOnboardingRequest request;
  final String cramKey;
  final AuthService _authService = AuthService();

  static Future<AtOnboardingResponse?> show(
    BuildContext context, {
    required AtOnboardingRequest request,
    required String cramKey,
  }) async {
    return await showDialog<AtOnboardingResponse>(
      context: context,
      builder: (context) => CramDialog(request: request, cramKey: cramKey),
    );
  }


  @override
  Widget build(BuildContext context) {
    _authService.onboard(request, cramKey).then((response) {
      print(response.toString());
    });
    return AlertDialog(
      title: Text("Onboarding"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder(stream: _authService.progressStream, builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return LoadingDialog(title: "Onboarding atSign via cram", description: "Authenticating ${request.atSign}, please wait...");
            }
            final progress = snapshot.data as ProgressEvent;
            if (progress.type == ProgressEventType.success) {
              return  Text("Onboarding Successful");
            } else if (progress.type == ProgressEventType.error) {
              return Text("Error: ${progress.msg}");
            }else{
              return Text("${progress.type} | ${progress.group} : ${progress.msg}");
            }
          }),
        ]
      ),
    );
  }
}