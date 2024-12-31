import 'package:apkam_example/authorisation/pages/otp_page.dart';
import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:apkam_example/theme/theme_constants.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../../theme/at_theme.dart';
import '../models/models.dart';
import '../widgets/authorisation_list_tile.dart';
import '../widgets/manager_device_card.dart';
import 'authorisation_page_section.dart';

class AuthorisationHomePage extends StatefulWidget {
  const AuthorisationHomePage({
    this.selectedSection = AuthorisationPageSection.otp,
    super.key,
  });

  final AuthorisationPageSection selectedSection;

  @override
  AuthorisationHomePageState createState() => AuthorisationHomePageState();
}

class AuthorisationHomePageState extends State<AuthorisationHomePage> {
  late AuthorisationPageSection selectedSection = widget.selectedSection;
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);

  late Future<bool> isManagerKey;
  late Future<Otp> getOtp;

  @override
  void initState() {
    super.initState();
    isManagerKey = service.isManagerKey();
    getOtp = service.generateOtp();
  }

  void updateSelectedSection(AuthorisationPageSection section) {
    setState(() {
      selectedSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AtTheme(
      child: Scaffold(
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
                      SizedBox(
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
                                          updateSelectedSection(AuthorisationPageSection.requests);
                                        },
                                        isSelected: selectedSection == AuthorisationPageSection.requests,
                                        badgeCount: 4,
                                      ),
                                      AuthorisationListTile(
                                        leading: AuthorisationPageSection.otp.icon,
                                        title: AuthorisationPageSection.otp.title(context),
                                        onTap: () {
                                          updateSelectedSection(AuthorisationPageSection.otp);
                                        },
                                        isSelected: selectedSection == AuthorisationPageSection.otp,
                                        trailing: FutureBuilder<Otp>(
                                          future: getOtp,
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const Center(
                                                child: CircularProgressIndicator(),
                                              );
                                            }
                                            if (snapshot.hasError) {
                                              return Text('Error: ${snapshot.error}');
                                            }
                                            return Row(
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
                                                      snapshot.data!.otp,
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
                                                  onPressed: () {},
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      AuthorisationListTile(
                                        leading: AuthorisationPageSection.setPin.icon,
                                        title: AuthorisationPageSection.setPin.title(context),
                                        onTap: () {
                                          updateSelectedSection(AuthorisationPageSection.setPin);
                                        },
                                        isSelected: selectedSection == AuthorisationPageSection.setPin,
                                      ),
                                      AuthorisationListTile(
                                        leading: AuthorisationPageSection.approvedEnrollments.icon,
                                        title: AuthorisationPageSection.approvedEnrollments.title(context),
                                        onTap: () {
                                          updateSelectedSection(AuthorisationPageSection.approvedEnrollments);
                                        },
                                        isSelected: selectedSection == AuthorisationPageSection.approvedEnrollments,
                                      ),
                                      AuthorisationListTile(
                                        leading: AuthorisationPageSection.history.icon,
                                        title: AuthorisationPageSection.history.title(context),
                                        onTap: () {
                                          updateSelectedSection(AuthorisationPageSection.history);
                                        },
                                        isSelected: selectedSection == AuthorisationPageSection.history,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: OutlinedButton.icon(
                                  label: const Text('Backup atSign'),
                                  icon: const Icon(Icons.backup_outlined),
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: switch (selectedSection) {
                            AuthorisationPageSection.otp => OtpPage(getOtp: getOtp),
                            // TODO: Handle this case.
                            AuthorisationPageSection.setPin => throw UnimplementedError(),
                            // TODO: Handle this case.
                            AuthorisationPageSection.requests => throw UnimplementedError(),
                            // TODO: Handle this case.
                            AuthorisationPageSection.approvedEnrollments => throw UnimplementedError(),
                            // TODO: Handle this case.
                            AuthorisationPageSection.history => throw UnimplementedError(),
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
      ),
    );
  }
}
