import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class TypableDropdown extends StatelessWidget {
  final List<String> items;
  final String? initialValue;
  final ValueChanged<String?>? onChanged;
  final String Function(String)? valueNormalizer;
  final String? hintText;
  final InputDecoration? decoration;

  const TypableDropdown({
    super.key,
    required this.items,
    this.initialValue,
    this.onChanged,
    this.valueNormalizer,
    this.hintText,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue ?? ''),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return items;
        return items.where(
          (item) =>
              item.toLowerCase().contains(textEditingValue.text.toLowerCase()),
        );
      },
      onSelected: (value) {
        final normalized = valueNormalizer?.call(value) ?? value;
        onChanged?.call(normalized);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 200, maxWidth: 360),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final item = options.elementAt(index);
                    return GestureDetector(
                      onTap: () => onSelected(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                        ),
                        child: Text(item, style: TextStyle(fontSize: 16)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration:
              decoration ??
              InputDecoration(
                hintText: hintText ?? 'Type to search...',
                hintStyle: TextStyle(fontSize: 12),
                border: OutlineInputBorder(),
                suffixIcon: GestureDetector(
                  onTap: () {
                    controller.clear();
                    focusNode.requestFocus();
                  },
                  child: PhosphorIcon(PhosphorIcons.caretDown()),
                ),
              ),
          onChanged: (value) {
            var normalized = valueNormalizer?.call(value) ?? value;
            if (normalized != value) {
              controller.value = TextEditingValue(
                text: normalized,
                selection: TextSelection.collapsed(offset: normalized.length),
              );
            }
            onChanged?.call(normalized.isEmpty ? null : normalized);
          },
        );
      },
    );
  }
}
