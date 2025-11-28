import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/widgets/shared/typable_dropdown.dart';
import 'package:flutter/material.dart';


/// A dialog widget that allows users to select or input an atSign and optionally a root domain.
/// 
/// Use `AtSignSelectionDialog.show` to display the dialog and retrieve the user's selection.
class AtSignSelectionDialog extends StatefulWidget {
  final ThemeData themeData;
  final List<String>? existingAtSigns;
  final Map<String, AtRootDomain>? existingDomains;
  const AtSignSelectionDialog({
    super.key,
    required this.themeData,
    this.existingAtSigns,
    this.existingDomains,
  });

  @override
  State<AtSignSelectionDialog> createState() =>
      _AtSignSelectionDialogState();


  /// Displays the AtSignSelectionDialog and returns an AuthRequest based on user input.
  /// - [context]: BuildContext to display the dialog.
  /// - [themeData]: ThemeData for styling the dialog.
  /// - [existingAtSigns]: Inject atsigns via file or keychain storage so that user can select them from a dropdown.
  /// - [existingDomains]: Inject root domains for selection (default: root.atsign.org:64).
  static Future<AuthRequest?> show(
    BuildContext context, {
    required ThemeData themeData,
    List<String>? existingAtSigns,
    Map<String, AtRootDomain>? existingDomains,
  }) {
    existingDomains ??= {'root.atsign.org': AtRootDomain.atsignDomain};
    return showDialog<AuthRequest>(
      context: context,
      builder: (context) => AtSignSelectionDialog(
        existingAtSigns: existingAtSigns,
        existingDomains: existingDomains,
        themeData: themeData,
      ),
    );
  }
}

class _AtSignSelectionDialogState
    extends State<AtSignSelectionDialog> {
  bool _isExpanded = false;
  String? _selectedAtSign;
  String? _selectedDomain;
  final TextEditingController _atSignTextController = TextEditingController();
  final TextEditingController _domainTextController = TextEditingController();

  Widget _buildInfoIcon(String tooltipText) {
    return Tooltip(
      message: tooltipText,
      child: Icon(
      Icons.info_outline,
      size: 16,
      color: Colors.grey[600],
      ),
    );
  }

 Widget _buildDropdownField({
  required TextEditingController controller,
  required String hint,
  required String infoText,
  required String labelText,
  required List<String>? items,
  required Function(String?) onChanged,
}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(children: [
       Row(
          children: [
          Text(
            labelText,
            style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: widget.themeData.primaryColor,
            ),
          ),
          const SizedBox(width: 6),
          _buildInfoIcon(infoText),
          ],
        ),
      const SizedBox(height: 16),
      TypableDropdown(
        items: items ?? [],
        hintText: hint,
        onChanged: onChanged,
      ),
      const SizedBox(height: 16),
    ],
    ),
  );
}

  void _handleSubmit() {
    if (_selectedAtSign != null) {
        AtOnboardingRequest request = AtOnboardingRequest(
          _selectedAtSign!,
        );
        if (_selectedDomain != null && _selectedDomain!.isNotEmpty) {
          var split = _selectedDomain!.split(':');
          String rootDomain = split[0];
          int rootPort = split.length > 1 ? int.parse(split[1]) : 64;
          request.rootDomain = AtRootDomain(
            rootDomain,
            rootPort,
          );
        }
        Navigator.of(context).pop(request);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
            children: [
      
            // atSign Dropdown
            _buildDropdownField(
              labelText: 'Type or select an atSign',
              infoText: "Select an atSign to proceed with onboarding.",
              hint: 'Type atSign or select from existing',
              controller: _atSignTextController,
              items: widget.existingAtSigns,
              onChanged: (value) {
              setState(() {
                _selectedAtSign = value;
              });
              },
            ),
            const SizedBox(height: 16),
            // Show/Hide Advanced Options
            InkWell(
              onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
              },
              child: 
              Container(alignment: Alignment.center,
                child: Row(
                  children: [
                    Icon(
                    _isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                    size: 20,
                    color: widget.themeData.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                    _isExpanded
                      ? 'Hide Advanced Options'
                      : 'Show Advanced Options',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: widget.themeData.primaryColor,
                    ),
                    ),
                  ],
                ),
              ),
            ),

            // Advanced Options (Expandable)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Domain Field
                _buildDropdownField(
                  labelText: 'Type or select a domain',
                  infoText: "Specify root domain if different from default. Only for custom implementations.",
                  hint: 'Type domain or select from existing',
                  controller: _domainTextController,
                  items: widget.existingDomains?.values.map((domain) => "${domain.rootDomain}:${domain.rootPort}").toList(),
                  onChanged: (value) {
                    setState(() {
                    _selectedDomain = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
              ],
              ),
              crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
              onPressed: (_selectedAtSign != null && _selectedAtSign!.isNotEmpty) ? _handleSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.themeData.colorScheme.secondary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                elevation: 0,
                shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                ),
              ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _atSignTextController.dispose();
    _domainTextController.dispose();
    super.dispose();
  }
}