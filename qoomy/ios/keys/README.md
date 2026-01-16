# APNs Authentication Key

## File: AuthKey_W8B39A3XRD.p8

**Purpose:** Apple Push Notifications service (APNs) authentication key for iOS push notifications via Firebase Cloud Messaging (FCM).

**Key ID:** W8B39A3XRD

**Team ID:** H86Y6XK238

**Created:** January 2026

## Usage

This key is uploaded to Firebase Console:
- Firebase Console → Project Settings → Cloud Messaging → Apple app configuration
- Upload the .p8 file with the Key ID and Team ID

## Important

- This key can only be downloaded once from Apple Developer Portal
- Keep this file secure and do not commit to public repositories
- Add `ios/keys/*.p8` to .gitignore

## Related Files

- `lib/services/push_notification_service.dart` - Flutter FCM token handling
- `functions/index.js` - Cloud Function that sends push notifications
