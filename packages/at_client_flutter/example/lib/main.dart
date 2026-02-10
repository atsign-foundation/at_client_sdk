import 'package:flutter/material.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:example/walkthrough.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:async';

final AtSignLogger _logger = AtSignLogger('main');

void main() {
  // Capture all errors in the Flutter framework
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _logger.info(
      '╔════════════════════════════════════════════════════════════════',
    );
    _logger.info('║ FLUTTER ERROR CAUGHT');
    _logger.info(
      '╠════════════════════════════════════════════════════════════════',
    );
    _logger.info('║ ${details.exception}');
    _logger.info(
      '╠════════════════════════════════════════════════════════════════',
    );
    _logger.info('║ Stack trace:');
    _logger.info('║ ${details.stack}');
    _logger.info(
      '╚════════════════════════════════════════════════════════════════',
    );
  };

  // Capture all errors outside of Flutter framework
  runZonedGuarded(
    () {
      runApp(const MyApp());
    },
    (error, stack) {
      _logger.info(
        '╔════════════════════════════════════════════════════════════════',
      );
      _logger.info('║ ASYNC ERROR CAUGHT');
      _logger.info(
        '╠════════════════════════════════════════════════════════════════',
      );
      _logger.info('║ Error: $error');
      _logger.info('║ Type: ${error.runtimeType}');
      _logger.info(
        '╠════════════════════════════════════════════════════════════════',
      );
      _logger.info('║ Stack trace:');
      _logger.info('║ $stack');
      _logger.info(
        '╚════════════════════════════════════════════════════════════════',
      );
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,

        // Scaffold theme
        scaffoldBackgroundColor: Colors.white,

        // AppBar theme
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),

        // Text theme
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          bodyMedium: TextStyle(fontSize: 14),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          bodySmall: TextStyle(fontSize: 13),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),

        // Elevated button theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // Outlined button theme
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            elevation: 0,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // Text button theme
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),

        // Divider theme
        dividerTheme: const DividerThemeData(thickness: 1),
      ),
      // Add a global builder to catch any remaining errors
      builder: (context, widget) {
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'An error occurred',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      errorDetails.exception.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        // Try to recover by navigating to home
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const MyHomePage()),
                          (route) => false,
                        );
                      },
                      child: const Text('Return to Home'),
                    ),
                  ],
                ),
              ),
            ),
          );
        };
        return widget!;
      },
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      // Uses theme.scaffoldBackgroundColor automatically
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Title - using theme text style
                Text('My App', style: textTheme.headlineMedium),

                const SizedBox(height: 8),

                // Subtitle - using theme text style with color modification
                Text(
                  'Secure authentication with atSign',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),

                const SizedBox(height: 48),

                // Login Button - now calls loginWithKeychain
                ElevatedButton(
                  onPressed: () async {
                    _logger.info('═══ Login with Keychain button pressed ═══');
                    try {
                      await loginWithKeychain(context);
                    } catch (e, stack) {
                      _logger.info('CAUGHT in button handler: $e');
                      _logger.info('Stack: $stack');
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: const Text('Login with Existing atSign'),
                ),
                const SizedBox(height: 16),

                // Login Button via enrollment
                ElevatedButton(
                  onPressed: () async {
                    _logger.info('═══ Login with APKAM button pressed ═══');
                    try {
                      await loginWithApkam(context);
                    } catch (e, stack) {
                      _logger.info('CAUGHT in button handler: $e');
                      _logger.info('Stack: $stack');
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: const Text('Register an atSign with APKAM'),
                ),
                const SizedBox(height: 16),

                // Divider with "OR" - using theme divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 16),

                // Register Button - now says "Onboard a New atSign"
                OutlinedButton(
                  onPressed: () async {
                    _logger.info('═══ Onboard button pressed ═══');
                    try {
                      await onboard(context);
                    } catch (e, stack) {
                      _logger.info('CAUGHT in button handler: $e');
                      _logger.info('Stack: $stack');
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    side: BorderSide(
                      color: colorScheme.primary.withOpacity(0.5),
                    ),
                  ),
                  child: const Text('Onboard a New atSign'),
                ),

                const SizedBox(height: 16),

                // NEW: Add atSign by File Button
                OutlinedButton(
                  onPressed: () async {
                    _logger.info('═══ Login with File button pressed ═══');
                    try {
                      await loginWithFile(context);
                    } catch (e, stack) {
                      _logger.info('CAUGHT in button handler: $e');
                      _logger.info('Stack: $stack');
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.secondary,
                    side: BorderSide(
                      color: colorScheme.secondary.withOpacity(0.5),
                    ),
                  ),
                  child: const Text('Add an atSign by File'),
                ),

                const SizedBox(height: 16),

                // Manage Paired atSigns text button - using theme
                TextButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      builder: (BuildContext context) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header - using theme text style
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Text(
                                  'Manage Paired atSigns',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(
                                      0.8,
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(),

                              // Clear atSign option - using theme colors
                              ListTile(
                                leading: Icon(
                                  Icons.clear,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('Clear atSign'),
                                onTap: () async {
                                  try {
                                    await removeAtsign(context);
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  } catch (e, stack) {
                                    _logger.info('Error removing atSign: $e');
                                    _logger.info('Stack: $stack');
                                  }
                                },
                              ),

                              // Reset all atSigns option - using theme colors
                              ListTile(
                                leading: Icon(
                                  Icons.restore,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('Reset All atSigns'),
                                onTap: () async {
                                  try {
                                    Navigator.pop(context);
                                    await clearAllAtsigns();
                                  } catch (e, stack) {
                                    _logger.info(
                                      'Error clearing all atSigns: $e',
                                    );
                                    _logger.info('Stack: $stack');
                                  }
                                },
                              ),

                              const SizedBox(height: 10),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  child: Text(
                    'Manage Paired atSigns',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Footer text - using theme text style
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      Text(
                        "Don't have an atSign yet?",
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Get a free atSign at atsign.com',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    bool _isExporting = false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        automaticallyImplyLeading: false, // Removes back button
      ),
      body: Center(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () {
                try {
                  AtClientManager.getInstance().reset();
                  // Navigate back to login page
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const MyHomePage()),
                  );
                } catch (e, stack) {
                  _logger.info('Error during logout: $e');
                  _logger.info('Stack: $stack');
                }
              },
              child: const Text('Logout'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                _logger.info('═══ Export Keys button pressed ═══');
                try {
                  await exportKeys(context);
                } catch (e, stack) {
                  _logger.info('CAUGHT in export button handler: $e');
                  _logger.info('Stack: $stack');
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Export error: $e')));
                  }
                }
              },
              icon: const Icon(Icons.download),
              label: Text('Export AtSign Keys'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
