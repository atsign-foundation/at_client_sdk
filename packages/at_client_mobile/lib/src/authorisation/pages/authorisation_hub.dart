import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_constants.dart';
import '../notifiers/authorisation_notifiers.dart';
import '../providers/authorisation_providers.dart';
import '../widgets/authorisation_section_list.dart';
import 'approved_enrollments_page.dart';
import 'authorisation_page_section.dart';
import 'enrollment_history_page.dart';
import 'otp_page.dart';
import 'requests_page.dart';
import 'set_pin_page.dart';

class AuthorisationHub extends StatefulWidget {
  const AuthorisationHub({
    required this.service,
    this.initialSelectedSection = AuthorisationPageSection.requests,
    this.themeData,
    super.key,
  });

  final AuthorisationService service;
  final AuthorisationPageSection initialSelectedSection;
  final ThemeData? themeData;

  @override
  AuthorisationHubState createState() => AuthorisationHubState();
}

class AuthorisationHubState extends State<AuthorisationHub> {
  AuthorisationService get service => widget.service;

  late final pendingRequestsNotifier = PendingRequestsNotifier(service);

  late Future<bool> isManagerKeyFuture;

  @override
  void initState() {
    super.initState();
    isManagerKeyFuture = service.isManagerKey();
  }

  @override
  void dispose() {
    pendingRequestsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AtTheme(
      themeData: widget.themeData,
      child: SelectedSectionProvider(
        notifier: SelectedSectionNotifier(
          initialSection: widget.initialSelectedSection,
        ),
        child: AuthorisationServiceProvider(
          service: service,
          // Needed here for showing the OTP in the section list
          child: ActiveOtpProvider(
            notifier: ActiveOtpNotifier(service),
            // Needed for showing the number of requests in the section list
            child: PendingRequestsProvider(
              notifier: pendingRequestsNotifier,
              child: Builder(
                builder: (context) {
                  final selectedSection = SelectedSectionProvider.of(context).selectedSection;
                  return FutureBuilder<bool>(
                    future: isManagerKeyFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.error,
                              color: Theme.of(context).colorScheme.error,
                              size: 42,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              snapshot.error.toString(),
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    isManagerKeyFuture = service.isManagerKey();
                                  });
                                },
                                child: const Text('Retry'),
                              ),
                            ),
                          ],
                        );
                      }
                      final isManagerKey = snapshot.data as bool;
                      if (!isManagerKey) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.warning,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 42,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your key is not a manager key',
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      } else {
                        return Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AuthorisationSectionList(),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Builder(
                                    builder: (context) {
                                      switch (selectedSection) {
                                        case AuthorisationPageSection.requests:
                                          return const RequestsPage();
                                        case AuthorisationPageSection.otp:
                                          return const OtpPage();
                                        case AuthorisationPageSection.setPin:
                                          return SppProvider(
                                            notifier: SppNotifier(service),
                                            child: const SetPinPage(),
                                          );
                                        case AuthorisationPageSection.approvedEnrollments:
                                          return ApprovedRequestsProvider(
                                            notifier: ApprovedRequestsNotifier(service),
                                            child: const ApprovedEnrollmentsPage(),
                                          );
                                        case AuthorisationPageSection.history:
                                          return const EnrollmentHistoryPage();
                                        default:
                                          return const SizedBox.shrink();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
