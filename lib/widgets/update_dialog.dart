import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../services/update_service.dart';

class UpdateDialog extends StatelessWidget {
  final Map<String, dynamic> updateInfo;
  final bool forceUpdate;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.forceUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latestVersion = updateInfo['latestVersion'];
    final currentVersion = updateInfo['currentVersion'];
    final updateNotes = updateInfo['updateNotes'];
    final downloadUrl = updateInfo['downloadUrl'];

    return PopScope(
      canPop: !forceUpdate, // Prevent closing if force update
      child: AlertDialog(
        title: Text(
          'Update Available',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A new version of Energenius is available!'),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'Current version: '),
                    TextSpan(
                      text: currentVersion,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'New version: '),
                    TextSpan(
                      text: latestVersion,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('What\'s new:', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  updateNotes ?? 'Bug fixes and performance improvements',
                ),
              ),
              if (forceUpdate) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This update is required to continue using the app',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: () {
                if (latestVersion != null) {
                  UpdateService().skipUpdateForVersion(latestVersion);
                }
                Navigator.of(context).pop(false);
              },
              child: const Text('Skip'),
            ),
          if (!forceUpdate)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Later'),
            ),
          FilledButton.icon(
            onPressed: () async {
              if (downloadUrl != null) {
                // Store context.mounted before the async gap
                final bool wasAlreadyMounted = context.mounted;
                final success = await UpdateService().launchUpdateUrl(
                  downloadUrl,
                );

                if (success) {
                  if (wasAlreadyMounted && context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                } else {
                  if (wasAlreadyMounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open download link'),
                      ),
                    );
                  }
                }
              } else {
                developer.log('No download URL available');
                Navigator.of(context).pop(false);
              }
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}
