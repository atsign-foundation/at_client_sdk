import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/authorisation/widgets/authorisation_feedback_overlay.dart';
import 'package:flutter/material.dart';

import '../providers/authorisation_providers.dart';
import '../widgets/authorisation_section_header.dart';
import '../widgets/enrollment_request_card.dart';
import 'authorisation_page_section.dart';

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  RequestsPageState createState() => RequestsPageState();
}

class RequestsPageState extends State<RequestsPage> {
  OverlayEntry? overlayEntry;

  void showHighlightOverlay({required ServerEnrollmentRequest request, required EnrollmentStatus newStatus}) {
    removeHighlightOverlay();

    overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Theme(
          data: Theme.of(context),
          child: Positioned(
            top: 30,
            right: 30,
            child: AuthorisationFeedbackOverlay(
              request: request,
              newStatus: newStatus,
              onTap: () {
                removeHighlightOverlay();
              },
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(overlayEntry!);
  }

  void removeHighlightOverlay() {
    overlayEntry?.remove();
    overlayEntry?.dispose();
    overlayEntry = null;
  }

  @override
  void dispose() {
    removeHighlightOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequestsProvider = PendingRequestsProvider.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.requests.title(context),
            icon: AuthorisationPageSection.requests.icon,
          ),
          if (pendingRequestsProvider.isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (pendingRequestsProvider.error != null)
            Center(
              child: Text(
                pendingRequestsProvider.error!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          if (pendingRequestsProvider.requests.isEmpty && pendingRequestsProvider.error == null)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No pending requests'),
            ),
          if (pendingRequestsProvider.requests.isNotEmpty && pendingRequestsProvider.error == null)
            ...pendingRequestsProvider.requests.map(
              (request) => EnrollmentRequestCard(
                request: request,
                onApprove: () async {
                  await pendingRequestsProvider.approveRequest(request);
                  if (pendingRequestsProvider.error == null) {
                    showHighlightOverlay(request: request, newStatus: EnrollmentStatus.approved);
                  }
                },
                onReject: () async {
                  await pendingRequestsProvider.denyRequest(request);
                  if (pendingRequestsProvider.error == null) {
                    showHighlightOverlay(request: request, newStatus: EnrollmentStatus.denied);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
