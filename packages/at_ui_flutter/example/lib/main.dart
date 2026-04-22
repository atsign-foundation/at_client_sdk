import 'package:at_ui_flutter/at_ui_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const AtsignCatalogApp());
}

class AtsignCatalogApp extends StatelessWidget {
  const AtsignCatalogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atsign Design System',
      theme: AtTheme.light, // Injecting our global safety net!
      home: const CatalogHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CatalogHomePage extends StatelessWidget {
  const CatalogHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AtColors>()!;
    final typography = Theme.of(context).extension<AtTypography>()!;
    final spacing = Theme.of(context).extension<AtSpacing>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Atsign Components')),
      body: ListView(
        padding: EdgeInsets.all(spacing.s24), // Using our updated token!
        children: [
          _buildSectionHeader('Typography', typography.h1),

          Text('Heading 1', style: typography.h1),
          Text('Heading 2', style: typography.h2),
          Text('Heading 3', style: typography.h3),
          Text('Heading 4', style: typography.h4),
          AtGap.h32,

          Text('Body Large (SemiBold)', style: typography.bodyLgSemiBold),
          Text('Body Large (Medium)', style: typography.bodyLgMedium),
          Text('Body Large (Regular)', style: typography.bodyLgRegular),
          AtGap.h16,

          Text('Body Medium (SemiBold)', style: typography.bodyMdSemiBold),
          Text('Body Medium (Medium)', style: typography.bodyMdMedium),
          Text('Body Medium (Regular)', style: typography.bodyMdRegular),
          AtGap.h16,
          Text('Body Small (SemiBold)', style: typography.bodySmSemiBold),
          Text('Body Small (Medium)', style: typography.bodySmMedium),
          Text('Body Small (Regular)', style: typography.bodySmRegular),
          AtGap.h16,
          Text('Body Extra Small (SemiBold)', style: typography.bodyXsSemiBold),
          Text('Body Extra Small (Medium)', style: typography.bodyXsMedium),
          Text('Body Extra Small (Regular)', style: typography.bodyXsRegular),
          AtGap.h16,
          Text('Body Extra Small (SemiBold)', style: typography.bodyXsSemiBold),
          Text('Body Extra Small (Medium)', style: typography.bodyXsMedium),
          Text('Body Extra Small (Regular)', style: typography.bodyXsRegular),
          AtGap.h16,
          Text(
            'Body Extra Extra Small (SemiBold)',
            style: typography.bodyXxsSemiBold,
          ),
          Text(
            'Body Extra Extra Small (Medium)',
            style: typography.bodyXxsMedium,
          ),
          Text(
            'Body Extra Extra Small (Regular)',
            style: typography.bodyXxsRegular,
          ),
          AtGap.h16,
          Text('Button Extra Large (Medium)', style: typography.buttonXl),
          Text('Button Large (Medium)', style: typography.buttonLg),
          Text('Button Medium (Medium)', style: typography.buttonMd),
          Text('Button Small (Medium)', style: typography.buttonSm),
          Text('Button Extra Small (Medium)', style: typography.buttonXs),

          AtGap.h16,
          const Divider(),
          AtGap.h16,

          _buildSectionHeader('Buttons', typography.h2),
          Wrap(
            spacing: spacing.s12,
            runSpacing: spacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Primary', style: typography.bodyXxsSemiBold),
              AtButton.primary(
                label: 'Small',
                size: AtButtonSize.small,
                onPressed: () {},
              ),
              AtButton.primary(
                label: 'Medium',
                size: AtButtonSize.medium,
                onPressed: () {},
              ),
              AtButton.primary(
                label: 'Large',
                size: AtButtonSize.large,
                onPressed: () {},
              ),

              AtButton.primary(
                label: 'Icon',
                leadingIcon: const Icon(
                  Icons.add,
                ), // Icon inherits white foreground automatically!
                trailingIcon: const Icon(
                  Icons.add,
                ), // Icon inherits white foreground automatically!
                onPressed: () {},
              ),
              AtButton.primary(label: 'Disabled', onPressed: null),
              AtButton.primary(
                label: 'Loading',
                onPressed: () {},
                isLoading: true,
              ),
            ],
          ),
          AtGap.h16,
          Wrap(
            spacing: spacing.s8,
            runSpacing: spacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Secondary', style: typography.bodyXxsSemiBold),
              AtButton.secondary(
                label: 'Small',
                size: AtButtonSize.small,
                onPressed: () {},
              ),
              AtButton.secondary(
                label: 'Medium',
                size: AtButtonSize.medium,
                onPressed: () {},
              ),
              AtButton.secondary(
                label: 'Large',
                size: AtButtonSize.large,
                onPressed: () {},
              ),
              AtButton.secondary(
                label: 'Icon',
                leadingIcon: const Icon(
                  Icons.add,
                ), // Icon inherits white foreground automatically!
                trailingIcon: const Icon(
                  Icons.add,
                ), // Icon inherits white foreground automatically!
                onPressed: () {},
              ),
              AtButton.secondary(label: 'Disabled', onPressed: null),
              AtButton.secondary(
                label: 'Loading',
                onPressed: () {},
                isLoading: true,
              ),
            ],
          ),
          AtGap.h16,
          Wrap(
            spacing: spacing.s12,
            runSpacing: spacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Tertiary', style: typography.bodyXxsSemiBold),
              AtButton.tertiary(
                label: 'Small',
                size: AtButtonSize.small,
                onPressed: () {},
              ),
              AtButton.tertiary(
                label: 'Medium',
                size: AtButtonSize.medium,
                onPressed: () {},
              ),
              AtButton.tertiary(
                label: 'Large',
                size: AtButtonSize.large,
                onPressed: () {},
              ),
              AtButton.tertiary(
                label: 'Icon',
                leadingIcon: const Icon(
                  Icons.add,
                ), // Icon inherits white foreground automatically!
                trailingIcon: const Icon(
                  Icons.add,
                ), // Icon inherits white foreground automatically!
                onPressed: () {},
              ),
              AtButton.tertiary(label: 'Disabled', onPressed: null),
              AtButton.tertiary(
                label: 'Loading',
                onPressed: () {},
                isLoading: true,
              ),
            ],
          ),
          AtGap.h16,
          Wrap(
            spacing: spacing.s12,
            runSpacing: spacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Warning', style: typography.bodyXxsSemiBold),
              AtButton.warning(
                label: 'Small',
                size: AtButtonSize.small,
                onPressed: () {},
              ),
              AtButton.warning(
                label: 'Medium',
                size: AtButtonSize.medium,
                onPressed: () {},
              ),
              AtButton.warning(
                label: 'Large',
                size: AtButtonSize.large,
                onPressed: () {},
              ),
              AtButton.warning(
                label: 'Icon',
                leadingIcon: const Icon(Icons.add),
                trailingIcon: const Icon(Icons.add),
                onPressed: () {},
              ),
              AtButton.warning(label: 'Disabled', onPressed: null),
              AtButton.warning(
                label: 'Loading',
                onPressed: () {},
                isLoading: true,
              ),
            ],
          ),
          AtGap.h16,
          Wrap(
            spacing: spacing.s12,
            runSpacing: spacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Link', style: typography.bodyXxsSemiBold),
              AtButton.link(
                label: 'Small',
                size: AtButtonSize.small,
                onPressed: () {},
              ),
              AtButton.link(
                label: 'Medium',
                size: AtButtonSize.medium,
                onPressed: () {},
              ),
              AtButton.link(
                label: 'Large',
                size: AtButtonSize.large,
                onPressed: () {},
              ),
              AtButton.link(
                label: 'Icon',
                leadingIcon: const Icon(Icons.add),
                trailingIcon: const Icon(Icons.add),
                onPressed: () {},
              ),
              AtButton.link(label: 'Disabled', onPressed: null),
              AtButton.link(
                label: 'Loading',
                onPressed: () {},
                isLoading: true,
              ),
            ],
          ),

          AtGap.h32,
          const Divider(),
          AtGap.h32,

          _buildSectionHeader('Tokens - Colors & Radius', typography.h2),
          Wrap(
            spacing: spacing.s16,
            children: [
              _ColorSwatch(
                color: colors.primary.shade500,
                label: 'Primary 500',
              ),
              _ColorSwatch(
                color: colors.secondary.shade500,
                label: 'Secondary 500',
              ),
              _ColorSwatch(color: colors.error.shade500, label: 'Error 500'),
            ],
          ),

          AtGap.h48, // Give some breathing room at the bottom
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, TextStyle textStyle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(title, style: textStyle),
    );
  }
}

/// A small internal widget just to display color squares in the catalog
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String label;

  const _ColorSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final radius = Theme.of(context).extension<AtRadius>()!;
    final typography = Theme.of(context).extension<AtTypography>()!;

    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius.md), // Testing AtRadius
            boxShadow: Theme.of(
              context,
            ).extension<AtElevation>()!.neutral2, // Testing AtElevation
          ),
        ),
        AtGap.h8,
        Text(label, style: typography.bodyXsRegular),
      ],
    );
  }
}
