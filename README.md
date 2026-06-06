# Secure Messenger

Secure Messenger is a Flutter mobile messaging app built with Supabase. It includes email authentication, user profiles, contact discovery, QR contact sharing, realtime chat, media messages, biometric login, and one-on-one secret chats with end-to-end encryption.

The app supports iOS and Android project targets. Supabase is used as the Firebase-style backend for Auth, Postgres, Realtime, and Storage.

## Features

### Authentication

- Email/password login and signup with Supabase Auth.
- New users create a profile with display name, username, and optional profile photo.
- Biometric login with Face ID or fingerprint through `local_auth`.
- Biometric credentials are stored with `flutter_secure_storage`.

### User Profiles

- Profile photo upload.
- Editable display name, username, bio, and phone number.
- Profile QR code generation.
- QR payload includes user id, username, display name, photo URL, and bio.

### Contacts

- Search users by username.
- Add contacts from search results.
- Add contacts by scanning profile QR codes.
- Contact actions for normal chat or secret chat.

### Messaging

- Realtime one-on-one chats.
- Text, image, video, and audio-file messages.
- Media preview before sending.
- Upload progress/loading indicators for media.
- Read receipts.
- Typing indicators.
- Edit sent messages.
- Delete sent messages for all participants.
- Private `chat-media` Supabase Storage bucket with signed URLs.

### Secret Chats

- One-on-one encrypted chats.
- Text messages are encrypted before being saved to Supabase.
- Image, video, and audio files are encrypted before upload.
- Secret chat messages stored in Supabase are ciphertext, not readable plaintext.
- Each secret chat uses an AES-GCM chat key.
- The chat key is wrapped for each participant using RSA-OAEP identity public keys.
- Private identity keys and chat keys stay on-device in secure storage.

## Tech Stack

| Area | Technology |
| --- | --- |
| App framework | Flutter |
| Backend | Supabase Auth, Postgres, Realtime, Storage |
| State management | Provider |
| Local security | flutter_secure_storage |
| Biometrics | local_auth |
| Encryption | pointycastle RSA-OAEP + AES-GCM |
| QR codes | qr_flutter, mobile_scanner |
| Media | image_picker, file_picker, video_player, cached_network_image |

## Project Setup

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Create Supabase Project

1. Create a Supabase project.
2. Go to Authentication > Providers > Email.
3. Enable Email auth.
4. For testing, disable email confirmation so new users can sign in immediately.
5. Go to SQL Editor.
6. Run the full contents of `supabase_schema.sql`.

The schema creates:

- `profiles`
- `contacts`
- `chats`
- `messages`
- `profile-photos` storage bucket
- `chat-media` storage bucket
- realtime publication entries for `profiles`, `chats`, and `messages`
- RLS policies for profiles, contacts, chats, messages, and storage
- helper functions for adding contacts and marking chats as read

### 3. Configure Supabase Keys

Create or update `lib/supabase_options.dart`:

```dart
class SupabaseOptions {
  static const url = 'https://YOUR_PROJECT_REF.supabase.co';
  static const anonKey = 'YOUR_SUPABASE_ANON_KEY';
}
```

Use the Project URL and anon public key from Supabase Project Settings > API.

## Run the App

Run on a connected device or simulator:

```bash
flutter run
```

If Flutter asks for a device, choose the iOS simulator, Android emulator, or connected phone.

For iOS after dependency changes:

```bash
cd ios
pod install
cd ..
flutter run
```

For Android, make sure the Android SDK is installed and `ANDROID_HOME` is configured.

## Verification Commands

```bash
dart format lib test
flutter analyze
flutter test
flutter build ios --debug --no-codesign
flutter build apk --debug
```

Current local verification:

| Check | Result |
| --- | --- |
| `flutter analyze` | Passed |
| `flutter test` | Passed |
| `flutter build ios --debug --no-codesign` | Passed |
| `flutter build apk --debug` | Not run locally because Android SDK is not configured in this terminal |

## Functional Checklist

| Requirement | Status |
| --- | --- |
| App has login/signup | Done |
| New user signup and login | Done |
| User authentication | Done |
| Profile with picture, username, and extra info | Done |
| Profile QR code | Done |
| QR contains profile information | Done |
| Biometric authentication | Done |
| Search users | Done |
| Add contacts by username search | Done |
| Add contacts by QR scan | Done |
| Create one-on-one chats | Done |
| Realtime text messages | Done |
| Image messages | Done |
| Video messages | Done |
| Audio-file messages | Done |
| Read receipts | Done |
| Typing indicators | Done |
| Edit sent messages | Done |
| Delete sent messages | Done |
| Secret one-on-one chats | Done |
| Secret chat text encryption | Done |
| Secret chat media encryption | Done |
| iOS target | Done |
| Android target | Done, requires Android SDK to build locally |

## How To Demo

1. Run the app on two devices or two simulators.
2. Create two accounts.
3. Add profile photos during signup or from the Profile tab.
4. Open Profile > My QR Code on one account.
5. Scan that QR code from Contacts on the other account.
6. Add the user as a contact.
7. Start a normal chat and send text, image, video, and audio files.
8. Confirm the other user receives messages and media.
9. Open the chat on the recipient side and check that read receipts update on the sender side.
10. Type from one user and confirm the typing indicator appears for the other.
11. Long-press a sent message to edit or delete it.
12. Start a Secret Chat from the contact action sheet.
13. Send secret text and media.
14. In Supabase, inspect `messages.content` for the secret chat: secret text content should be encrypted payloads, not plaintext.

## Security Notes

- Normal chats are realtime and protected by Supabase RLS, but message text is stored as plaintext.
- Secret chats encrypt text with AES-GCM before writing to Supabase.
- Secret media is encrypted before upload to Storage.
- AES-GCM uses a fresh nonce per payload.
- Secret chat keys are encrypted separately for each participant using RSA-OAEP.
- Device private keys are stored locally in `flutter_secure_storage`.
- Supabase RLS restricts chat and media access to chat participants.
- Biometric authentication uses OS APIs; the app never receives raw biometric data.

## Troubleshooting

### Signup Works But Profile Error Briefly Appears

This is handled in the auth provider by treating the profile lookup as a short Supabase timing race during account creation. If it appears again, fully restart the app instead of hot reload.

### iOS Pod or Framework Issues

Run:

```bash
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter run
```

The project pins `path_provider_foundation` to avoid the iOS `objective_c.framework` signing problem seen on some Xcode setups.

### Local Network Warning on iOS

If Flutter says it cannot access the local network, grant permission in macOS System Settings > Privacy & Security > Local Network for the terminal or IDE running Flutter.

### Android SDK Missing

Install Android Studio or the Android command-line tools, then set `ANDROID_HOME`. After that, run:

```bash
flutter doctor
flutter build apk --debug
```
