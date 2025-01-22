import 'package:flutter/material.dart';

import '../providers/spp_provider.dart';
import '../widgets/authorisation_section_header.dart';
import '../widgets/spp_widget.dart';
import 'authorisation_page_section.dart';

class SetPinPage extends StatefulWidget {
  const SetPinPage({super.key});

  @override
  SetPinPageState createState() => SetPinPageState();
}

class SetPinPageState extends State<SetPinPage> {
  @override
  Widget build(BuildContext context) {
    final sppNotifier = SppProvider.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.setPin.title(context),
            icon: AuthorisationPageSection.setPin.icon,
          ),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Create a memorable PIN to use when onboarding your atSign in other apps and devices.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  if (sppNotifier.fetchError != null)
                    Text(
                      sppNotifier.fetchError!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  if (sppNotifier.fetchError == null) const SppWidget(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
