import 'package:duration/duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../providers/spp_provider.dart';
import 'spp_expiration.dart';

class SppWidget extends StatefulWidget {
  const SppWidget({
    this.characterCount = 6,
    super.key,
  });

  final int characterCount;

  @override
  SppWidgetState createState() => SppWidgetState();
}

class SppWidgetState extends State<SppWidget> {
  static const _fieldHeight = 50.0;
  static const _fieldWidth = 44.0;
  static const _fieldPadding = 24.0;

  bool saveEnabled = false;

  late final formKey = GlobalKey<FormState>();
  // Controller is automatically disposed by PinCodeTextField
  late final _controller = TextEditingController();
  late final _durationOptions = const [
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];
  late var _selectedDuration = _durationOptions.first;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sppNotifer = SppProvider.of(context);
    if (sppNotifer.spp != null) {
      _controller.text = sppNotifer.spp!.otp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sppNotifer = SppProvider.of(context);

    return SizedBox(
      width: widget.characterCount * (_fieldWidth + _fieldPadding) + _fieldPadding * 2,
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(_fieldPadding),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sppNotifer.spp?.expiry != null && sppNotifer.spp!.expiry.isAfter(DateTime.now())) ...[
                  SppExpiration(
                      expiryTime: sppNotifer.spp!.expiry,
                      onExpiry: () {
                        _controller.clear();
                        setState(() {});
                      }),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Tooltip(
                      message: 'Duration before the pin expires',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'Duration:',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Expanded(
                      child: DropdownButton<Duration>(
                        underline: const SizedBox.shrink(),
                        value: _selectedDuration,
                        onChanged: (Duration? value) {
                          // This is called when the user selects an item.
                          if (value != null) {
                            setState(() {
                              _selectedDuration = value;
                            });
                          }
                        },
                        items: _durationOptions.map<DropdownMenuItem<Duration>>((e) {
                          return DropdownMenuItem<Duration>(
                            value: e,
                            child: Text(e.pretty()),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PinCodeTextField(
                  appContext: context,
                  controller: _controller,
                  length: widget.characterCount,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  textCapitalization: TextCapitalization.characters,
                  cursorColor: Theme.of(context).colorScheme.primary,
                  animationType: AnimationType.fade,
                  enableActiveFill: true,
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      saveEnabled = value.length == widget.characterCount;
                    });
                  },
                  pinTheme: PinTheme(
                    shape: PinCodeFieldShape.box,
                    borderRadius: BorderRadius.circular(4),
                    fieldHeight: _fieldHeight,
                    fieldWidth: _fieldWidth,
                    activeColor: Colors.transparent,
                    inactiveColor: Colors.transparent,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    activeFillColor: Theme.of(context).colorScheme.surface,
                    selectedFillColor: Theme.of(context).colorScheme.surface,
                    inactiveFillColor: Theme.of(context).colorScheme.surface,
                    borderWidth: 1,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: saveEnabled
                      ? () async {
                          await sppNotifer.setSpp(
                            _controller.text,
                            _selectedDuration,
                          );
                        }
                      : null,
                  child: sppNotifer.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : const Text('Save'),
                ),
                if (sppNotifer.error != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      sppNotifer.error!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection, // Preserve cursor position
    );
  }
}
