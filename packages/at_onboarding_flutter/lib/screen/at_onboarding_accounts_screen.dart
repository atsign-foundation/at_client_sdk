import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_dimens.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:flutter/material.dart';

/// This screen shows the list of atSign already available for the given email
class AtOnboardingAccountsScreen extends StatefulWidget {
  /// list of atSign for the email
  final List<String> atsigns;

  /// message to display along with the atSign list
  final String? message;

  /// the new atSign selected in the free atSign generator
  final String? newAtsign;

  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingAccountsScreen({
    Key? key,
    required this.atsigns,
    this.message,
    this.newAtsign,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingAccountsScreen> createState() =>
      _AtOnboardingAccountsScreenState();
}

class _AtOnboardingAccountsScreenState
    extends State<AtOnboardingAccountsScreen> {
  List<String> pairedAtsignsList = [];
  Object? lastSelectedIndex;
  late int greyStartIndex;

  Future<void> intifuture() async {
    pairedAtsignsList = await OnboardingService.getInstance().getAtsignList();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    intifuture();
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
            AtOnboardingLocalizations.current.select_atSign,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Text(
                widget.message ??
                    AtOnboardingLocalizations.current.title_select_atSign,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AtOnboardingDimens.fontNormal,
                ),
              ),
              const SizedBox(height: 10),
              if (widget.newAtsign != null) ...<Widget>[
                const Divider(thickness: 0.8),
                RadioListTile<Object>(
                  controlAffinity: ListTileControlAffinity.trailing,
                  groupValue: lastSelectedIndex,
                  onChanged: (Object? value) {
                    setState(() {
                      lastSelectedIndex = value;
                    });
                    _showAlert(widget.newAtsign!, context);
                  },
                  value: 'new',
                  activeColor: theme.primaryColor,
                  title: Text('@${widget.newAtsign}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
              const Divider(thickness: 0.8),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.atsigns.length,
                  itemBuilder: (BuildContext context, int index) {
                    String currentItem = '@${widget.atsigns[index]}';
                    bool isExist = pairedAtsignsList.contains(currentItem);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: RadioListTile<Object>(
                        controlAffinity: ListTileControlAffinity.trailing,
                        groupValue: lastSelectedIndex,
                        onChanged: isExist
                            ? null
                            : (Object? value) {
                                setState(() {
                                  lastSelectedIndex = value;
                                });
                                _showAlert(
                                  widget.atsigns[
                                      int.parse(lastSelectedIndex.toString())],
                                  context,
                                );
                              },
                        value: index,
                        activeColor: theme.primaryColor,
                        title: Text(currentItem),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<AlertDialog?> _showAlert(String atsign, BuildContext context) async {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    await showDialog<AlertDialog>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: AlertDialog(
          content: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyLarge,
              children: <InlineSpan>[
                TextSpan(
                  text:
                      AtOnboardingLocalizations.current.title_pair_atSign_prev,
                ),
                TextSpan(
                    text: ' $atsign ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(
                  text:
                      AtOnboardingLocalizations.current.title_pair_atSign_next,
                )
              ],
            ),
          ),
          actions: <Widget>[
            AtOnboardingSecondaryButton(
              height: 40,
              borderRadius: 20,
              onPressed: () => Navigator.pop(context),
              child: Text(
                AtOnboardingLocalizations.current.btn_cancel,
              ),
            ),
            AtOnboardingPrimaryButton(
              height: 40,
              borderRadius: 20,
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, atsign);
              },
              child: Text(
                AtOnboardingLocalizations.current.btn_yes_continue,
              ),
            )
          ],
        ),
      ),
    );
    return null;
  }
}
