import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';

import '../providers/free_atsign_notifier_provider.dart';
import '../providers/register_person_notifier_provider.dart';

class RegisterPersonSection extends StatefulWidget {
  const RegisterPersonSection({required this.onRegisterSuccess, super.key});

  final VoidCallback onRegisterSuccess;

  @override
  RegisterPersonSectionState createState() => RegisterPersonSectionState();
}

class RegisterPersonSectionState extends State<RegisterPersonSection> {
  late final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    super.dispose();
    _emailController.dispose();
  }

  Future<void> _submit() async {
    final registerPersonNotifier = RegisterPersonNotifierProvider.of(context);
    final freeAtSignNotifier = FreeAtsignNotifierProvider.of(context);
    if (_formKey.currentState!.validate()) {
      await registerPersonNotifier.registerPerson(
        _emailController.text.trim(),
        freeAtSignNotifier.freeAtsign!,
      );
      if (registerPersonNotifier.error == null) {
        widget.onRegisterSuccess();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final registerPersonNotifier = RegisterPersonNotifierProvider.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter your email address',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 8),
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _emailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            onFieldSubmitted: (_) async {
              await _submit();
            },
            validator: (value) {
              final trimmedValue = value?.trim();
              if (trimmedValue == null || trimmedValue.isEmpty) {
                return 'Please enter your email address';
              }
              if (!EmailValidator.validate(trimmedValue)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
            decoration: InputDecoration(
              prefixStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
              hintText: 'email@example.com',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text('Note: We do not share your personal information or use it for financial gain.'),
        SizedBox(height: 16),
        FilledButton.icon(
          onPressed: registerPersonNotifier.isFetching ? null : _submit,
          iconAlignment: IconAlignment.end,
          icon: Icon(Icons.arrow_forward),
          label: Text('Send Code'),
        ),
        SizedBox(height: 8),
        if (registerPersonNotifier.error != null)
          Text(
            registerPersonNotifier.error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
      ],
    );
  }
}
