import 'package:at_commons/at_commons.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import 'namespace_chip.dart';

class EnrollmentRequestCard extends StatefulWidget {
  const EnrollmentRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  final EnrollmentRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  State<EnrollmentRequestCard> createState() => _EnrollmentRequestCardState();
}

class _EnrollmentRequestCardState extends State<EnrollmentRequestCard> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SelectableText.rich(
                    TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      text: widget.request.appName,
                      children: [
                        TextSpan(
                          text: ' | ',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextSpan(
                          text: widget.request.deviceName,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '48 H left',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.end,
                )
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('${widget.request.namespacePermissions.length} Namespaces Affected'),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    isExpanded = !isExpanded;
                                  });
                                },
                                child: Text(
                                  isExpanded ? 'Show less' : 'More details',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          AnimatedSize(
                            alignment: Alignment.topCenter,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: AnimatedCrossFade(
                              duration: const Duration(milliseconds: 200),
                              firstCurve: Curves.easeInOut,
                              secondCurve: Curves.easeInOut,
                              sizeCurve: Curves.easeInOut,
                              crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                              firstChild: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                      alignment: WrapAlignment.start,
                                      runAlignment: WrapAlignment.start,
                                      crossAxisAlignment: WrapCrossAlignment.start,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: widget.request.namespacePermissions
                                          .map(
                                            (permission) => NamespaceChip(
                                              permission: permission,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SelectableText(
                                    'ID ${widget.request.enrollmentId}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  )
                                ],
                              ),
                              secondChild: const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all<OutlinedBorder>(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                    ),
                    foregroundColor: WidgetStateProperty.all<Color>(
                      Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    side: WidgetStateProperty.all<BorderSide>(
                      BorderSide(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    textStyle: WidgetStateProperty.all<TextStyle>(
                      Theme.of(context).textTheme.labelLarge!.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                      const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
                  onPressed: () {},
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    // return ListTile(
    //   title: Text(widget.request.appName),
    //   subtitle: Column(
    //     crossAxisAlignment: CrossAxisAlignment.start,
    //     mainAxisSize: MainAxisSize.min,
    //     children: [
    //       Text(widget.request.deviceName),
    //       Text(widget.request.namespacePermissions.map((permission) => permission.prettyPrint()).join(', ')),
    //     ],
    //   ),
    //   trailing: switch (widget.request.status) {
    //     EnrollmentStatus.pending => Row(
    //         mainAxisSize: MainAxisSize.min,
    //         children: [
    //           ElevatedButton(
    //             onPressed: widget.onApprove,
    //             child: Text('Approve'),
    //           ),
    //           ElevatedButton(
    //             onPressed: widget.onReject,
    //             child: Text('Reject'),
    //           ),
    //         ],
    //       ),
    //     EnrollmentStatus.approved => RawChip(
    //         label: Text('Approved'),
    //         color: WidgetStateProperty.all<Color>(Colors.green),
    //       ),
    //     EnrollmentStatus.denied => RawChip(
    //         label: Text('Denied'),
    //         color: WidgetStateProperty.all<Color>(Colors.red),
    //       ),
    //     EnrollmentStatus.revoked => RawChip(
    //         label: Text('Revoked'),
    //         color: WidgetStateProperty.all<Color>(Colors.orange),
    //       ),
    //     EnrollmentStatus.expired => RawChip(
    //         label: Text('Expired'),
    //         color: WidgetStateProperty.all<Color>(Colors.grey),
    //       ),
    //   },
    // );
  }
}

extension on NamespacePermission {
  String prettyPrint() {
    final buffer = StringBuffer();
    buffer.append(namespace);
    if (read) {
      buffer.append(' (read)');
    }
    if (write) {
      buffer.append(' (write)');
    }
    return buffer.getData()!;
  }
}
