import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/widgets/shared/typable_dropdown.dart';
import 'package:flutter/material.dart';

class AtSignSelectionDialog extends StatefulWidget {
  final List<String>? existingAtSigns;
  final Map<String, AtRootDomain>? existingDomains;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentTextColor;
  const AtSignSelectionDialog({
    super.key,
    this.existingAtSigns,
    this.existingDomains,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentTextColor,
  });

  @override
  State<AtSignSelectionDialog> createState() =>
      _AtSignSelectionDialogState();

  static Future<AtOnboardingRequest?> show(
    BuildContext context, {
    List<String>? existingAtSigns,
    Map<String, AtRootDomain>? existingDomains,
    required Color primaryColor,
    required Color secondaryColor,
    required Color accentTextColor,
  }) {
    return showDialog<AtOnboardingRequest>(
      context: context,
      builder: (context) => AtSignSelectionDialog(
        existingAtSigns: existingAtSigns,
        existingDomains: existingDomains,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        accentTextColor: accentTextColor,
      ),
    );
  }
}

class _AtSignSelectionDialogState
    extends State<AtSignSelectionDialog> {
  bool _isExpanded = false;
  String? _selectedAtSign;
  String? _selectedDomain;
  String? _selectedPort;
  final TextEditingController _atSignTextController = TextEditingController();
  final TextEditingController _domainTextController = TextEditingController();
  final TextEditingController _portTextController = TextEditingController();

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
  required String hint,
  required TextEditingController controller,
  required List<String>? items,
  required Function(String?) onChanged,
}) {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey[300]!),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(children: [
      TypableDropdown(
        items: items ?? [],
        hintText: hint,
        onChanged: onChanged,
      ),
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
          request.rootDomain = AtRootDomain(_selectedDomain!, int.parse(_selectedPort ?? '64'));
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
            // Title with info icon
            Row(
              children: [
              Text(
                'Select atSign',
                style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.primaryColor,
                ),
              ),
              const SizedBox(width: 6),
              _buildInfoIcon("Select an atSign to proceed with onboarding."),
              ],
            ),
            const SizedBox(height: 16),

            // atSign Dropdown
            _buildDropdownField(
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
            // Separator line
            Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.shade300,
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
                    color: widget.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                    _isExpanded
                      ? 'Hide Advanced Options'
                      : 'Show Advanced Options',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: widget.primaryColor,
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
                Row(
                children: [
                  Text(
                  'Domain',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.primaryColor,
                  ),
                  ),
                  const SizedBox(width: 6),
                  _buildInfoIcon("A custom root domain for custom environments. Don't set for production atSigns."),
                ],
                ),
                const SizedBox(height: 10),
                _buildDropdownField(
                hint: 'Type domain or select from existing',
                controller: _domainTextController,
                items: widget.existingDomains?.values.map((domain) => domain.rootDomain).toList(),
                onChanged: (value) {
                  setState(() {
                  _selectedDomain = value;
                  });
                },
                ),
                const SizedBox(height: 20),

                // Port Field
                Row(
                children: [
                  Text(
                  'Port',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.primaryColor,
                  ),
                  ),
                  const SizedBox(width: 6),
                  _buildInfoIcon("A custom port for custom environments. Don't set for production atSigns."),
                ],
                ),
                const SizedBox(height: 10),
                _buildDropdownField(
                hint: 'Type port or select from defaults',
                controller: _portTextController,
                items: widget.existingDomains?.values.map((domain) => domain.rootPort.toString()).toList(),
                onChanged: (value) {
                  setState(() {
                  _selectedPort = value;
                  });
                },
                ),
              ],
              ),
              crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),

            // Optional: Add a submit button
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
              onPressed: (_selectedAtSign != null && _selectedAtSign!.isNotEmpty) ? _handleSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.secondaryColor,
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
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _atSignTextController.dispose();
    _domainTextController.dispose();
    _portTextController.dispose();
    super.dispose();
  }
}