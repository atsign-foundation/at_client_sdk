import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../providers/spp_provider.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sppNotifer = SppProvider.of(context);
    // TODO: Create a timer to update the expiry time every second. Could do this here or in the notifier.
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
                if (sppNotifer.spp?.expiry != null) ...[
                  Text(
                    'Expires in ${sppNotifer.spp!.expiry.difference(DateTime.now()).inMinutes} minutes',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
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
                          await sppNotifer.setSpp(_controller.text);
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
