import 'package:flutter/material.dart';

import '../models/models.dart';
import 'namespace_chip.dart';

class EnrollmentRequestCard extends StatefulWidget {
  const EnrollmentRequestCard({
    required this.request,
    this.onApprove,
    this.onReject,
    this.onRevoke,
    super.key,
  });

  final ServerEnrollmentRequest request;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;
  final Future<void> Function()? onRevoke;

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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                // Duration is not available at the moment
                // Text(
                //   '48 H left',
                //   style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                //         color: Theme.of(context).colorScheme.onSurfaceVariant,
                //       ),
                //   textAlign: TextAlign.end,
                // ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 0,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                    '${widget.request.namespacePermissions.length} Namespaces Affected'),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
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
                              crossFadeState: isExpanded
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              firstChild: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                      alignment: WrapAlignment.start,
                                      runAlignment: WrapAlignment.start,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.start,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          widget.request.namespacePermissions
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
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
                if (widget.onReject != null)
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                        const EdgeInsets.symmetric(horizontal: 24),
                      ),
                    ),
                    onPressed: () async {
                      await widget.onReject!();
                    },
                    child: const Text('Reject'),
                  ),
                if (widget.onReject != null) const SizedBox(width: 8),
                if (widget.onApprove != null)
                  FilledButton(
                    onPressed: () async {
                      await widget.onApprove!();
                    },
                    child: const Text('Approve'),
                  ),
                if (widget.onApprove != null) const SizedBox(width: 8),
                if (widget.onRevoke != null)
                  FilledButton(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all<Color>(
                        Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    onPressed: () async {
                      final result = await showGeneralDialog<bool>(
                        context: context,
                        pageBuilder: (dialogContext, animation1, animation2) {
                          return Theme(
                            data: Theme.of(context),
                            child: AlertDialog(
                              title: const Text('Revoke Enrollment'),
                              content: const Text(
                                  'Are you sure you want to revoke this enrollment?'),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop(false);
                                  },
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop(true);
                                  },
                                  child: const Text('Revoke'),
                                ),
                              ],
                            ),
                          );
                        },
                      );

                      if (result != null && result) {
                        await widget.onRevoke!();
                      }
                    },
                    child: const Text('Revoke'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
