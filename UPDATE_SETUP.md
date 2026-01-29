# App Update System Setup Guide

This document provides instructions for setting up the app version checking and update system in Firebase.

## Firebase Setup

1. Open the Firebase Console (https://console.firebase.google.com/)
2. Navigate to your project
3. Go to Firestore Database
4. Create a new collection called `app_versions`
5. Inside this collection, create a document with ID `latest`
6. Add the following fields to the document:

| Field Name   | Type   | Description                                         |
|--------------|--------|-----------------------------------------------------|
| version      | String | The latest version number (e.g., "1.0.1")           |
| buildNumber  | Number | The latest build number (e.g., 3)                   |
| updateNotes  | String | Notes describing what's new in this version         |
| forceUpdate  | Boolean| Whether users should be forced to update            |
| downloadUrl  | Map    | A map containing platform-specific download URLs    |

For the `downloadUrl` map, add the following fields:
- `android`: String URL to the Play Store or direct APK download link
- `ios`: String URL to the App Store

Example document:
```json
{
  "version": "1.0.1",
  "buildNumber": 3,
  "updateNotes": "- Added automatic update checking system
- App now notifies when a new version is available
- Various performance improvements and bug fixes",
  "forceUpdate": false,
  "downloadUrl": {
    "android": "https://play.google.com/store/apps/details?id=com.energenius.app",
    "ios": "https://apps.apple.com/us/app/energenius/id0000000000"
  }
}
```

## Releasing A New Version

When releasing a new version:

1. Update the version number and build number in `pubspec.yaml`
2. Update the document in Firebase with the new version details
3. If you want users to be forced to update (e.g., for critical changes), set `forceUpdate` to `true`

## Testing

To test the update system:
1. Set up the Firebase document with a higher version number than your current app version
2. Run the app and verify that the update dialog appears
3. Test both the "Skip", "Later", and "Update Now" actions
4. Test force updates by setting `forceUpdate` to `true`

## Security Rules

Make sure your Firestore security rules allow read-only access to the app_versions collection:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read-only access to app version information
    match /app_versions/{document=**} {
      allow read: if true;
      allow write: if false;
    }
    
    // ... your other rules ...
  }
}
```

## Troubleshooting

If the update dialog is not showing:
1. Make sure your device is connected to the internet
2. Check that the version in Firebase is higher than your app version
3. Check the logs for any errors during the update check
4. Verify that the app has the necessary permissions

If users cannot download the update:
1. Verify the download URLs in Firebase are correct
2. Ensure the app has been published to the respective app stores 