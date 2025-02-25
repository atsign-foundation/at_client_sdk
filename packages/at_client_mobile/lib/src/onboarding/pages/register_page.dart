import 'package:at_client_mobile/src/onboarding/pages/register_free_atsign_page.dart';
import 'package:at_client_mobile/src/onboarding/pages/register_otp_page.dart';
import 'package:flutter/material.dart';

import 'register_person_page.dart';

enum _RegisterPages {
  freeAtsign,
  registerPerson,
  otpRequired,
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({required this.onCramKeyReceived, super.key});

  final ValueChanged<String> onCramKeyReceived;

  @override
  RegisterPageState createState() => RegisterPageState();
}

class RegisterPageState extends State<RegisterPage> {
  late _RegisterPages _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = _RegisterPages.freeAtsign;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Builder(
        builder: (context) {
          switch (_currentPage) {
            case _RegisterPages.freeAtsign:
              return FreeAtsignPage(
                onSubmit: () {
                  setState(() {
                    _currentPage = _RegisterPages.registerPerson;
                  });
                },
              );
            case _RegisterPages.registerPerson:
              return RegisterPersonPage(
                onRegisterSuccess: () {
                  setState(() {
                    _currentPage = _RegisterPages.otpRequired;
                  });
                },
              );
            case _RegisterPages.otpRequired:
              return RegisterOtpPage(
                onCramKeyReceived: widget.onCramKeyReceived,
              );
          }
        },
      ),
    );
  }
}
