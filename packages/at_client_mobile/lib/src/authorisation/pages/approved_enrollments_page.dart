import 'package:flutter/material.dart';

import '../providers/authorisation_providers.dart';
import '../widgets/authorisation_section_header.dart';
import '../widgets/enrollment_request_card.dart';
import 'authorisation_page_section.dart';

class ApprovedEnrollmentsPage extends StatefulWidget {
  const ApprovedEnrollmentsPage({super.key});

  @override
  ApprovedEnrollmentsPageState createState() => ApprovedEnrollmentsPageState();
}

class ApprovedEnrollmentsPageState extends State<ApprovedEnrollmentsPage> {
  @override
  Widget build(BuildContext context) {
    final approvedRequestsProvider = ApprovedRequestsProvider.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.approvedEnrollments.title(context),
            icon: AuthorisationPageSection.approvedEnrollments.icon,
          ),
          if (approvedRequestsProvider.isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (approvedRequestsProvider.error != null)
            Center(
              child: Text(
                approvedRequestsProvider.error!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          if (approvedRequestsProvider.requests.isEmpty && !approvedRequestsProvider.isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No pending requests'),
            ),
          if (approvedRequestsProvider.requests.isNotEmpty && !approvedRequestsProvider.isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: SearchBar(
                leading: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                hintText: 'Search',
              ),
            ),
          if (approvedRequestsProvider.requests.isNotEmpty && !approvedRequestsProvider.isLoading)
            ...approvedRequestsProvider.requests.map(
              (request) => EnrollmentRequestCard(
                request: request,
                onRevoke: () async {
                  await approvedRequestsProvider.revokeRequest(request);
                },
              ),
            ),
        ],
      ),
    );
  }
}
