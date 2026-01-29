import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();

  factory UpdateService() => _instance;

  UpdateService._internal();

  /// Checks if there is a newer version of the app available.
  /// Returns a map containing update information or null if no update is available.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.parse(packageInfo.buildNumber);

      developer.log('Current app version: $currentVersion+$currentBuildNumber');

      // Check the latest version from Firebase
      final updateDoc =
          await FirebaseFirestore.instance
              .collection('app_versions')
              .doc('latest')
              .get();

      if (!updateDoc.exists) {
        developer.log('No version information found in Firebase');
        return null;
      }

      final latestVersion = updateDoc.data()?['version'] as String;
      final latestBuildNumber = updateDoc.data()?['buildNumber'] as int;
      final updateNotes = updateDoc.data()?['updateNotes'] as String?;
      final forceUpdate = updateDoc.data()?['forceUpdate'] as bool? ?? false;
      final downloadUrl =
          updateDoc.data()?['downloadUrl'] as Map<String, dynamic>?;

      // Parse versions to compare them
      final List<int> currentParts =
          currentVersion.split('.').map(int.parse).toList();
      final List<int> latestParts =
          latestVersion.split('.').map(int.parse).toList();

      // Compare major, minor, and patch versions
      bool needsUpdate = false;

      // Compare major version
      if (latestParts[0] > currentParts[0]) {
        needsUpdate = true;
      }
      // Same major version, compare minor
      else if (latestParts[0] == currentParts[0] &&
          latestParts[1] > currentParts[1]) {
        needsUpdate = true;
      }
      // Same major and minor version, compare patch
      else if (latestParts[0] == currentParts[0] &&
          latestParts[1] == currentParts[1] &&
          latestParts[2] > currentParts[2]) {
        needsUpdate = true;
      }
      // If versions are the same, compare build number
      else if (latestParts[0] == currentParts[0] &&
          latestParts[1] == currentParts[1] &&
          latestParts[2] == currentParts[2] &&
          latestBuildNumber > currentBuildNumber) {
        needsUpdate = true;
      }

      if (needsUpdate) {
        String? url;
        if (downloadUrl != null) {
          if (Platform.isAndroid) {
            url = downloadUrl['android'] as String?;
          } else if (Platform.isIOS) {
            url = downloadUrl['ios'] as String?;
          }
        }

        return {
          'currentVersion': currentVersion,
          'latestVersion': latestVersion,
          'updateNotes':
              updateNotes ?? 'Bug fixes and performance improvements',
          'forceUpdate': forceUpdate,
          'downloadUrl': url,
        };
      }

      return null; // No update needed
    } catch (e) {
      developer.log('Error checking for updates: $e');
      return null;
    }
  }

  /// Launch the URL to download the update
  Future<bool> launchUpdateUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      developer.log('Error launching URL: $e');
      return false;
    }
  }

  /// Check if update check should be skipped for this version
  Future<bool> shouldSkipUpdateCheck(String version) async {
    final prefs = await SharedPreferences.getInstance();
    final skippedVersion = prefs.getString('skipped_update_version');
    return skippedVersion == version;
  }

  /// Save skipped version to preferences
  Future<void> skipUpdateForVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('skipped_update_version', version);
  }

  /// Clear skipped version from preferences
  Future<void> clearSkippedUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('skipped_update_version');
  }
}
