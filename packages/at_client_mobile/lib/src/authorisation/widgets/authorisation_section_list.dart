import 'package:flutter/material.dart';

import '../../theme/theme_constants.dart';
import '../pages/authorisation_page_section.dart';
import '../providers/authorisation_providers.dart';
import 'authorisation_list_tile.dart';
import 'manager_device_card.dart';

class AuthorisationSectionList extends StatefulWidget {
  const AuthorisationSectionList({super.key});

  @override
  AuthorisationSectionListState createState() => AuthorisationSectionListState();
}

class AuthorisationSectionListState extends State<AuthorisationSectionList> {
  @override
  Widget build(BuildContext context) {
    final selectedSection = SelectedSectionProvider.of(context).selectedSection;
    final activeOtp = ActiveOtpProvider.of(context);
    return SizedBox(
      width: 400,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const ManageDeviceCard(),
                    const SizedBox(height: 24),
                    AuthorisationListTile(
                      leading: AuthorisationPageSection.requests.icon,
                      title: AuthorisationPageSection.requests.title(context),
                      onTap: () {
                        SelectedSectionProvider.of(context).updateSelectedSection(AuthorisationPageSection.requests);
                      },
                      isSelected: selectedSection == AuthorisationPageSection.requests,
                      badgeCount: PendingRequestsProvider.of(context).requests.length,
                    ),
                    AuthorisationListTile(
                      leading: AuthorisationPageSection.otp.icon,
                      title: AuthorisationPageSection.otp.title(context),
                      onTap: () {
                        SelectedSectionProvider.of(context).updateSelectedSection(AuthorisationPageSection.otp);
                      },
                      isSelected: selectedSection == AuthorisationPageSection.otp,
                      // TODO: Create a nicer loading state
                      trailing: activeOtp.isFetching
                          ? const SizedBox(
                              height: 30,
                              width: 30,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : activeOtp.error != null
                              ? Text('Error: ${activeOtp.error!}')
                              : Row(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: selectedSection == AuthorisationPageSection.otp
                                            ? Theme.of(context).colorScheme.surfaceContainerHigh
                                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(
                                          activeOtp.otp!.otp,
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                color: selectedSection == AuthorisationPageSection.otp
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Theme.of(context).colorScheme.onSurface,
                                              ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Copy OTP',
                                      icon: Icon(
                                        Icons.copy,
                                        color: selectedSection == AuthorisationPageSection.otp
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                      // TODO: Add in functionality to copy OTP
                                      onPressed: () {},
                                    ),
                                  ],
                                ),
                    ),
                    AuthorisationListTile(
                      leading: AuthorisationPageSection.setPin.icon,
                      title: AuthorisationPageSection.setPin.title(context),
                      onTap: () {
                        SelectedSectionProvider.of(context).updateSelectedSection(AuthorisationPageSection.setPin);
                      },
                      isSelected: selectedSection == AuthorisationPageSection.setPin,
                    ),
                    AuthorisationListTile(
                      leading: AuthorisationPageSection.approvedEnrollments.icon,
                      title: AuthorisationPageSection.approvedEnrollments.title(context),
                      onTap: () {
                        SelectedSectionProvider.of(context)
                            .updateSelectedSection(AuthorisationPageSection.approvedEnrollments);
                      },
                      isSelected: selectedSection == AuthorisationPageSection.approvedEnrollments,
                    ),
                    // AuthorisationListTile(
                    //   leading: AuthorisationPageSection.history.icon,
                    //   title: AuthorisationPageSection.history.title(context),
                    //   onTap: () {
                    //     SelectedSectionProvider.of(context).updateSelectedSection(AuthorisationPageSection.history);
                    //   },
                    //   isSelected: selectedSection == AuthorisationPageSection.history,
                    // ),
                  ],
                ),
              ),
            ),
            // Padding(
            //   padding: const EdgeInsets.all(16.0),
            //   child: OutlinedButton.icon(
            //     label: const Text('Backup atSign'),
            //     icon: const Icon(Icons.backup_outlined),
            //     onPressed: () {},
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
