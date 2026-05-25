# SecureMessenger

A secure mobile messaging app built with Flutter and Supabase, featuring biometric authentication, end-to-end encrypted secret chats, and realtime messaging.

## Features

- **Login / Signup** — Email and password authentication via Supabase Auth
- **Biometric Auth** — Fingerprint / Face ID unlock using `local_auth`
- **User Profile** — Display name, username, bio, phone, profile photo, QR code
- **Search Users** — Search by username with live results
- **Add Contacts** — Via username search or QR code scan
- **Regular Chat** — Text, image, video, and audio-file messages
  - Read receipts
  - Typing indicators
  - Edit and delete messages
- **Secret Chat** — End-to-end encrypted one-on-one chats
  - RSA identity keys are generated on-device; private keys stay in secure storage
  - Each secret chat uses a shared AES-GCM key wrapped separately for each participant
  - Secret text, images, videos, and audio files are encrypted before Supabase upload

## Tech Stack

| Layer | Technology |
|-------|------------|
| Framework | Flutter |
| Backend | Supabase Auth, Postgres, Realtime, Storage |
| State Management | Provider |
| Encryption | `pointycastle` RSA-OAEP + AES-GCM, `flutter_secure_storage` |
| Biometrics | `local_auth` |
| QR | `qr_flutter`, `mobile_scanner` |
| Media | `image_picker`, `file_picker`, `video_player`, `cached_network_image` |

## Supabase Setup

1. Create a project at https://supabase.com.
2. Open **Authentication → Providers → Email**.
3. Enable **Email** auth. For easier testing, disable email confirmation.
4. Open **SQL Editor**.
5. Paste and run the full contents of `supabase_schema.sql`.
6. Open **Project Settings → API**.
7. Copy:
   - Project URL
   - anon public key
8. Put them in `lib/supabase_options.dart`:

```dart
class SupabaseOptions {
  static const url = 'https://YOUR_PROJECT_REF.supabase.co';
  static const anonKey = 'YOUR_SUPABASE_ANON_KEY';
}
```

The SQL file creates:

- `profiles`
- `contacts`
- `chats`
- `messages`
- `profile-photos` storage bucket
- `chat-media` storage bucket
- Row Level Security policies for authenticated users and chat participants

## Run

```bash
flutter pub get
flutter run
```

## Security Notes

- Secret chats use AES-GCM with a fresh nonce per encrypted payload.
- Secret chat keys are stored locally and are only stored in Supabase after RSA-OAEP wrapping for each participant.
- Secret media is encrypted before upload.
- Supabase RLS policies restrict profile/contact/chat/message/storage access.
- Chat media bucket is private; the app creates short-lived signed URLs for regular media viewing.
- Biometric authentication uses OS-level APIs; raw biometric data is never accessed.

## Audit Checklist

| Feature | Status |
|---------|--------|
| App runs without crashing | ✅ after Supabase config |
| Login / Signup page | ✅ |
| User authentication | ✅ |
| User profile with photo, username, bio | ✅ |
| QR code generation | ✅ |
| Biometric authentication | ✅ |
| Search users by username | ✅ |
| Add contacts by search + QR scan | ✅ |
| Send text messages | ✅ |
| Send images | ✅ |
| Send videos | ✅ |
| Send audio files | ✅ |
| Read receipts | ✅ |
| Typing indicators | ✅ |
| Edit messages | ✅ |
| Delete messages | ✅ |
| Secret chat E2E encryption | ✅ |
| iOS support | ✅ |
| Android support | ✅ |
