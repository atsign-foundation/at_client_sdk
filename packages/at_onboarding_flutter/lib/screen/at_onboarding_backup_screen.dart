import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/services/at_onboarding_backup_service.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_app_constants.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_dimens.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_strings.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:flutter/material.dart';

/// This screen is for backing up an atKey during onboarding
class AtOnboardingBackupScreen extends StatefulWidget {
  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingBackupScreen({
    Key? key,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingBackupScreen> createState() =>
      _AtOnboardingBackupScreenState();
}

class _AtOnboardingBackupScreenState extends State<AtOnboardingBackupScreen> {
  String? atsign;
  bool isSaveAtSign = false;
  final OnboardingService _onboardingService = OnboardingService.getInstance();
  final _atOnboardingBackupService = AtOnboardingBackupService.instance;

  @override
  void initState() {
    super.initState();
    atsign = _onboardingService.currentAtsign;

    _atOnboardingBackupService.setRemindBackup(remind: true);
    _atOnboardingBackupService.setBackupOpenedTime(dateTime: DateTime.now());
  }

  GlobalKey globalKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      textTheme: widget.config.theme?.textTheme,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    if (atsign == null) {
      return Text(
        AtOnboardingLocalizations.current.msg_atSign_required,
      );
    }

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(
            AtOnboardingLocalizations.current.title_save_your_key,
          ),
          leading: Container(),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(AtOnboardingDimens.paddingNormal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 10),
              Text(
                AtOnboardingLocalizations.current.title_important,
                style: const TextStyle(
                  fontSize: AtOnboardingDimens.fontLarge,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                AtOnboardingLocalizations
                    .current.msg_save_atKey_in_secure_location,
                style: const TextStyle(fontSize: AtOnboardingDimens.fontNormal),
                textAlign: TextAlign.center,
              ),
              Expanded(
                flex: 1,
                child: Container(),
              ),
              Center(
                child: Image.asset(
                  AtOnboardingStrings.backupZip,
                  height: Platform.isAndroid || Platform.isIOS
                      ? MediaQuery.of(context).size.height * 0.3
                      : 250,
                  width: Platform.isAndroid || Platform.isIOS
                      ? MediaQuery.of(context).size.height * 0.3
                      : 250,
                  fit: BoxFit.fill,
                  package: AtOnboardingConstants.package,
                  color: theme.iconTheme.color,
                ),
              ),
              Expanded(flex: 1, child: Container()),
              Container(
                constraints: const BoxConstraints(
                  maxWidth: 400,
                ),
                child: AtOnboardingPrimaryButton(
                  height: 48,
                  borderRadius: 24,
                  child: Text(AtOnboardingLocalizations.current.btn_save),
                  onPressed: () async {
                    _atOnboardingBackupService.setRemindBackup(remind: false);
                    final widget = BackupKeyWidget(atsign: atsign ?? '');
                    final result = await widget.showBackupDialog(context);

                    if (result == true) {
                      setState(() {
                        isSaveAtSign = true;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(
                  maxWidth: 400,
                ),
                child: AtOnboardingSecondaryButton(
                  height: 48,
                  borderRadius: 24,
                  onPressed: _handleRemindLatter,
                  child: Text(
                    isSaveAtSign
                        ? AtOnboardingLocalizations.current.btn_continue
                        : AtOnboardingLocalizations.current.btn_remind_me_later,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleRemindLatter() {
    Navigator.pop(context);
    if (!isSaveAtSign) {
      _atOnboardingBackupService.setRemindBackup(remind: true);
      _atOnboardingBackupService.setBackupOpenedTime(
        dateTime: DateTime.now(),
      );
    }
  }
}
