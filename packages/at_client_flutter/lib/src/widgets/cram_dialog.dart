import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';

class CramDialog extends StatefulWidget {
  const CramDialog({super.key, required this.request, required this.cramKey});

  final AtOnboardingRequest request;
  final String cramKey;
  @override
  CramDialogState createState() => CramDialogState();


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
}


class CramDialogState extends State<CramDialog> {
  AtOnboardingRequest get request => widget.request;
  String get cramKey => widget.cramKey;
  final AuthService _authService = AuthService();
  late Future<AtOnboardingResponse> future;

  @override
  void initState() {
    super.initState();
    future = _authService.onboard(request, cramKey);
  }

  @override
  Widget build(BuildContext context) {
    future.then((response) {
      Navigator.of(context).pop(response);
    });
    return AlertDialog(
      title: Text("Onboarding"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder(stream: _authService.progressStream, builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            final progress = snapshot.data as ProgressEvent;
            if (progress.type == ProgressEventType.success) {
              return SnackBar(content:  Text("Onboarding completed successfully!"));
            } else if (progress.type == ProgressEventType.error) {
              return SnackBar(content:  Text("Error during onboarding: ${progress.group}: ${progress.msg}"));
            }else{
              return SnackBar(content: Text("Onboarding ${progress.type}: ${progress.group}: ${progress.msg}"));
            }
          }),
        ]
      ),
    );
  }
}