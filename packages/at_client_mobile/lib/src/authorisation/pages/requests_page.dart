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
          if (pendingRequestsProvider.requests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No pending requests'),
            ),
          if (pendingRequestsProvider.requests.isNotEmpty)
            ...pendingRequestsProvider.requests.map(
              (request) => EnrollmentRequestCard(
                request: request,
                onApprove: () async {
                  await pendingRequestsProvider.approveRequest(request);
                },
                onReject: () async {
                  await pendingRequestsProvider.denyRequest(request);
                },
              ),
            ),
        ],
      ),
    );
  }
}
