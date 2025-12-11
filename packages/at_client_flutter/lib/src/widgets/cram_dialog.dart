import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';

/// A dialog widget that facilitates onboarding an atSign using a CRAM key.
///
/// Use `CramDialog.show` to display the dialog and handle the onboarding process.
///
/// Required Parameters:
/// - [request]: An `AtOnboardingRequest` containing details for the onboarding process.
/// - [cramKey]: The CRAM key used for authentication during onboarding.
///
/// Optional Parameters:
/// - [title]: A title string for the dialog (default: "Onboarding atSign via cram").
/// - [description]: A description string displayed while onboarding is in progress (default: "Authenticating, please wait...").
/// - [progressBuilder]: An optional builder function to customize the display of progress events.
///   It takes a `ProgressEvent` and returns a `Widget`, allowing for tailored UI updates during the onboarding process.
///   Otherwise, by default it will pop the dialog with the progress event.
/// - [onOnboardingComplete]: An optional callback function that is invoked when the onboarding process completes successfully.
///
/// Returns:
/// - An `AtOnboardingResponse` upon successful onboarding, or null if the process fails or is cancelled.
class CramDialog extends StatelessWidget {
  CramDialog({
    super.key,
    required this.request,
    required this.cramKey,
    this.progressBuilder,
    this.onOnboardingComplete,
    this.title,
    this.description,
  });

  final AtOnboardingRequest request;
  final String cramKey;
  final AuthService _authService = AuthService();
  final Widget Function(ProgressEvent)? progressBuilder;
  final void Function(AtOnboardingRequest)? onOnboardingComplete;
  final String? title;
  final String? description;

  static Future<AtOnboardingResponse?> show(
    BuildContext context, {
    required AtOnboardingRequest request,
    required String cramKey,
    Widget Function(ProgressEvent)? progressBuilder,
    void Function(AtOnboardingRequest)? onOnboardingComplete,
    String? title,
    String? description,
  }) async {
    return await showDialog<AtOnboardingResponse>(
      context: context,
      builder: (context) => CramDialog(
        request: request,
        cramKey: cramKey,
        progressBuilder: progressBuilder,
        onOnboardingComplete: onOnboardingComplete,
        title: title,
        description: description,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _authService.onboard(request, cramKey).then((response) {
      if (onOnboardingComplete != null) {
        onOnboardingComplete!(request);
      } else {
        print(response.toString());
      }
      Navigator.of(context).pop(response);
    });
    return AlertDialog(
      title: Text("Onboarding"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        StreamBuilder(
            stream: _authService.progressStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return LoadingDialog(
                    title: title ?? "Onboarding atSign via cram",
                    description:
                        description ?? "Authenticating, please wait...");
              }
              final progress = snapshot.data as ProgressEvent;
              if (progressBuilder == null) {
                return Container();
              } else {
                return progressBuilder!(progress);
              }
            })
      ]),
    );
  }
}
