import 'package:apkam_example/authorisation/pages/approved_enrollments_page.dart';
import 'package:apkam_example/authorisation/pages/enrollment_history_page.dart';
import 'package:apkam_example/authorisation/pages/otp_page.dart';
import 'package:apkam_example/authorisation/pages/set_pin_page.dart';
import 'package:apkam_example/authorisation/providers/otp_provider.dart';
import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:apkam_example/authorisation/widgets/authorisation_section_list.dart';
import 'package:apkam_example/theme/theme_constants.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../../theme/at_theme.dart';
import '../providers/authorisation_service_provider.dart';
import '../providers/selected_section_provider.dart';
import 'authorisation_page_section.dart';
import 'requests_page.dart';

class AuthorisationHomePage extends StatefulWidget {
  const AuthorisationHomePage({
    this.initialSelectedSection = AuthorisationPageSection.otp,
    super.key,
  });

  final AuthorisationPageSection initialSelectedSection;

  @override
  AuthorisationHomePageState createState() => AuthorisationHomePageState();
}

class AuthorisationHomePageState extends State<AuthorisationHomePage> {
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);

  late Future<bool> isManagerKey;

  @override
  void initState() {
    super.initState();
    isManagerKey = service.isManagerKey();
  }

  @override
  Widget build(BuildContext context) {
    return AtTheme(
      child: SelectedSectionProvider(
        notifier: SelectedSection(
          initialSection: widget.initialSelectedSection,
        ),
        child: AuthorisationServiceProvider(
          service: service,
          child: ActiveOtpProvider(
            notifier: ActiveOtp(service),
            child: Builder(
              builder: (context) {
                final selectedSection = SelectedSectionProvider.of(context).selectedSection;
                return Scaffold(
                  appBar: AppBar(
                    title: Text(AtClientManager.getInstance().atClient.getCurrentAtSign()!),
                  ),
                  body: FutureBuilder<bool>(
                    future: isManagerKey,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text('Error ${snapshot.error}');
                      }
                      final isManagerKey = snapshot.data as bool;
                      if (!isManagerKey) {
                        return Text('Your key is not a manager key');
                      } else {
                        return Padding(
                          padding: const EdgeInsets.all(64.0),
                          child: Container(
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
                                    child: switch (selectedSection) {
                                      AuthorisationPageSection.requests => const RequestsPage(),
                                      AuthorisationPageSection.otp => const OtpPage(),
                                      AuthorisationPageSection.setPin => const SetPinPage(),
                                      AuthorisationPageSection.approvedEnrollments => const ApprovedEnrollmentsPage(),
                                      AuthorisationPageSection.history => const EnrollmentHistoryPage(),
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
