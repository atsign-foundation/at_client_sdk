import 'package:at_client_mobile/src/onboarding/providers/selected_atsign_notifier_provider.dart';
import 'package:flutter/material.dart';

import '../providers/login_notifier_provider.dart';

class OnboardingInitForm extends StatefulWidget {
  const OnboardingInitForm({
    required this.onRegisterPressed,
    super.key,
  });

  final VoidCallback onRegisterPressed;

  @override
  OnboardingInitFormState createState() => OnboardingInitFormState();
}

class OnboardingInitFormState extends State<OnboardingInitForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _atSignController;
  late final TextEditingController _directoryDomainController;
  late final TextEditingController _cramSecretController;

  @override
  void initState() {
    super.initState();
    _atSignController = TextEditingController();
    _directoryDomainController = TextEditingController();
    _cramSecretController = TextEditingController();
  }

  @override
  void dispose() {
    _atSignController.dispose();
    _directoryDomainController.dispose();
    _cramSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loginNotifier = LoginNotifierProvider.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'atSign',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Enter your atSign below or select one from the menu.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: 16),
          // TODO: Add some validation logic.
          TextFormField(
            controller: _atSignController,
            decoration: InputDecoration(
              labelText: 'atSign',
              prefix: Text('@'),
              prefixStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 24),
          ExpansionTile(
            title: Text(
              'What is an atSign?',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            leading: Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            childrenPadding: EdgeInsets.all(16),
            expandedAlignment: Alignment.centerLeft,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'An atSign is a unique identifier used to access data and services on the atProtocol.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          SizedBox(height: 24),
          ExpansionTile(
            title: Text('Advanced Configuration'),
            childrenPadding: EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            expandedAlignment: Alignment.centerLeft,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'atDirectory Domain',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Select or enter the domain.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: 16),
              // TODO: Add some validation logic.
              TextFormField(
                controller: _directoryDomainController,
                decoration: InputDecoration(
                  labelText: 'Root domain',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 24),
              Text(
                'CRAM Secret',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '(Optional) Enter your CRAM secret',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: 16),
              // TODO: Add some validation logic.
              TextFormField(
                controller: _cramSecretController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'CRAM secret',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: widget.onRegisterPressed,
                child: Text('Register'),
              ),
              FilledButton(
                onPressed: () async {
                  await loginNotifier.login(
                    atSign: _atSignController.text,
                    rootDomain: _directoryDomainController.text,
                    cramSecret: _cramSecretController.text,
                  );
                  if (loginNotifier.error == null) {
                    SelectedAtsignNotifierProvider.of(context).value = _atSignController.text;
                  }
                },
                child: Text('Login'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
