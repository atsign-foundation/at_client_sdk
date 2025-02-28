import 'package:flutter/material.dart';

import '../widgets/register_free_atsign_section.dart';
import '../widgets/register_otp_section.dart';
import '../widgets/register_person_section.dart';

enum RegisterPageSections {
  freeAtsign,
  registerPerson,
  otpRequired,
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    required this.onCramKeyReceived,
    required this.onBack,
    super.key,
  });

  final void Function(String cramSecret, String atSign) onCramKeyReceived;
  final VoidCallback onBack;

  @override
  RegisterPageState createState() => RegisterPageState();
}

class RegisterPageState extends State<RegisterPage> {
  late RegisterPageSections _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = RegisterPageSections.freeAtsign;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Builder(
        key: ValueKey(_currentPage),
        builder: (context) {
          switch (_currentPage) {
            case RegisterPageSections.freeAtsign:
              return RegisterFreeAtsignSection(
                onFreeAtsignSelect: () {
                  setState(() {
                    _currentPage = RegisterPageSections.registerPerson;
                  });
                },
                onBack: widget.onBack,
              );
            case RegisterPageSections.registerPerson:
              return RegisterPersonSection(
                onRegisterSuccess: () {
                  setState(() {
                    _currentPage = RegisterPageSections.otpRequired;
                  });
                },
              );
            case RegisterPageSections.otpRequired:
              return RegisterOtpSection(
                onCramKeyReceived: widget.onCramKeyReceived,
              );
          }
        },
      ),
    );
  }
}
