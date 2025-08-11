import 'package:at_onboarding_flutter/at_onboarding_result.dart';
import 'package:at_onboarding_flutter/localizations/generated/l10n.dart';
import 'package:at_onboarding_flutter/services/at_onboarding_config.dart';
import 'package:at_onboarding_flutter/services/sdk_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_dimens.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_error_util.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_dialog.dart';
import 'package:flutter/material.dart';

/// The screen is used for resetting the paired atSign
class AtOnboardingResetScreen extends StatefulWidget {
  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingResetScreen({
    Key? key,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingResetScreen> createState() => _AtOnboardingResetScreenState();
}

class _AtOnboardingResetScreenState extends State<AtOnboardingResetScreen> {
  List<String> atsignsList = [];
  Map<String, bool?> atsignMap = <String, bool>{};
  bool isSelectAll = false;

  @override
  void initState() {
    setup();
    super.initState();
  }

  void setup() async {
    atsignsList = await SDKService().getAtsignList() ?? [];
    for (String atsign in atsignsList) {
      atsignMap[atsign] = false;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      textTheme: widget.config.theme?.textTheme,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            AtOnboardingLocalizations.current.reset,
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              Navigator.of(context).pop(AtOnboardingResetResult.cancelled);
            },
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(
                AtOnboardingDimens.paddingNormal,
              ),
              child: Text(
                AtOnboardingLocalizations.current.reset_description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AtOnboardingDimens.fontNormal,
                ),
              ),
            ),
            Expanded(
              child: atsignsList.isEmpty ? _buildEmptyWidget() : _buildAtSignsWidget(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          AtOnboardingLocalizations.current.no_atSigns_paired_to_reset,
          style: const TextStyle(fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildAtSignsWidget(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CheckboxListTile(
          onChanged: (bool? value) {
            isSelectAll = value!;
            if (atsignMap.isNotEmpty) {
              atsignMap.updateAll((String? key, bool? value1) => value1 = value);
            }
            setState(() {});
          },
          value: isSelectAll,
          activeColor: theme.primaryColor,
          title: Text(
            AtOnboardingLocalizations.current.select_all,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AtOnboardingDimens.paddingNormal,
          ),
        ),
        Expanded(
            child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (String atsign in atsignsList)
                CheckboxListTile(
                  onChanged: (bool? value) {
                    if (atsignMap.isNotEmpty) {
                      atsignMap[atsign] = value;
                    }
                    setState(() {});
                  },
                  value: atsignMap.isNotEmpty ? atsignMap[atsign] : true,
                  activeColor: theme.primaryColor,
                  title: Text(atsign),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AtOnboardingDimens.paddingNormal,
                  ),
                )
            ],
          ),
        )),
        const Divider(),
        const SizedBox(
          height: 10,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AtOnboardingDimens.paddingNormal,
          ),
          child: Text(
            AtOnboardingLocalizations.current.msg_action_cannot_undone,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: AtOnboardingDimens.fontNormal,
            ),
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        Container(
          padding: EdgeInsets.only(
            left: AtOnboardingDimens.paddingNormal,
            right: AtOnboardingDimens.paddingNormal,
            bottom: AtOnboardingDimens.paddingNormal + MediaQuery.of(context).padding.bottom,
          ),
          constraints: const BoxConstraints(
            maxWidth: 400,
          ),
          child: AtOnboardingPrimaryButton(
            height: 48,
            borderRadius: 24,
            onPressed: _onResetPressed,
            child: Text(
              AtOnboardingLocalizations.current.remove,
            ),
          ),
        )
      ],
    );
  }

  void _onResetPressed() async {
    Map<String, bool?> tempAtsignMap = <String, bool>{};
    tempAtsignMap.addAll(atsignMap);
    tempAtsignMap.removeWhere((String? key, bool? value) => value == false);
    if (tempAtsignMap.keys.toList().isEmpty) {
      AtOnboardingDialog.showError(
        context: context,
        message: AtOnboardingLocalizations.current.select_atSign_to_reset,
      );
    } else {
      _resetDevice(tempAtsignMap.keys.toList());
    }
  }

  Future<void> _resetDevice(List<String> checkedAtsigns) async {
    await SDKService().resetAtsigns(checkedAtsigns).then((void value) async {
      if (mounted) {
        Navigator.pop(context, AtOnboardingResetResult.success);
      }
    }).catchError((Object error) {
      showErrorDialog(error);
    });
  }

  Future<void> showErrorDialog(dynamic errorMessage, {String? title}) async {
    String? messageString = AtOnboardingErrorToString().getErrorMessage(errorMessage);
    return AtOnboardingDialog.showError(context: context, message: messageString);
  }
}
