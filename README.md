# SecureMessenger

A secure mobile messaging app built with Flutter and Firebase, featuring end-to-end encryption, biometric authentication, and real-time messaging.

## Features

- **Login / Signup** — Email & password authentication via Firebase Auth
- **Biometric Auth** — Fingerprint / Face ID login using `local_auth`
- **User Profile** — Display name, username, bio, profile photo, QR code
- **Search Users** — Search by username with live results
- **Add Contacts** — Via username search or QR code scan
- **Regular Chat** — Text, image, and video messages
  - Read receipts (✓ sent, ✓✓ read)
  - Typing indicators (animated dots)
  - Edit & delete messages
- **Secret Chat** — AES-256 CBC end-to-end encrypted one-on-one chats
  - Keys stored locally in device secure storage (Keychain / Keystore)
  - Encrypted content is unreadable in Firestore backend
- **Dark Theme** — Modern dark UI throughout

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Backend | Firebase (Auth, Firestore, Storage) |
| State Management | Provider |
| Encryption | `encrypt` (AES-256 CBC) + `flutter_secure_storage` |
| Biometrics | `local_auth` |
| QR | `qr_flutter` + `mobile_scanner` |
| Media | `image_picker`, `video_player`, `cached_network_image` |

## Project Structure

```
lib/
├── core/
│   ├── constants/       # AppConstants (collection names, keys, timeouts)
│   ├── errors/          # AppException hierarchy + Firebase error mapping
│   ├── services/        # EncryptionService, BiometricService
│   └── theme/           # AppTheme (dark)
├── data/
│   ├── models/          # UserModel, ChatModel, MessageModel
│   └── repositories/   # AuthRepository, UserRepository, ChatRepository
├── firebase_options.dart  # ← YOU MUST FILL THIS IN (see setup below)
├── main.dart
└── presentation/
    ├── auth/            # Login, Signup screens + AuthProvider
    ├── chat/            # ChatScreen + MessageProvider
    ├── contacts/        # ContactsScreen + ContactsProvider
    ├── home/            # HomeScreen (tabbed navigation)
    ├── profile/         # ProfileScreen + ProfileProvider
    ├── secret_chat/     # SecretChatScreen + SecretMessageProvider
    └── widgets/         # Shared: AppButton, AppTextField, UserAvatar, ErrorBanner
```

## Firebase Setup (Required before running)

### 1. Create a Firebase Project

1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Click **Add project** → name it `secure-messenger`
3. Disable Google Analytics (optional) → **Create project**

### 2. Enable Firebase Services

In your Firebase project console:

- **Authentication** → Sign-in method → Enable **Email/Password**
- **Firestore Database** → Create database → Start in **production mode** → choose a region
- **Storage** → Get started → Start in **production mode**

### 3. Add Apps to Firebase

**Android:**
- Package name: `com.securemessenger.secure_messenger`
- Download `google-services.json` → place in `android/app/`

**iOS:**
- Bundle ID: `com.securemessenger.secureMessenger`
- Download `GoogleService-Info.plist` → place in `ios/Runner/`

### 4. Generate firebase_options.dart

```bash
# Install FlutterFire CLI (once)
dart pub global activate flutterfire_cli

# Configure (run from project root)
flutterfire configure --project=YOUR_PROJECT_ID
```

This auto-generates `lib/firebase_options.dart` with your real credentials, replacing the placeholder file.

### 5. Apply Firestore Security Rules

In Firebase Console → Firestore → Rules, paste the contents of `firestore.rules`.

### 6. Apply Storage Rules

In Firebase Console → Storage → Rules:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /profile_photos/{userId}.jpg {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    match /chat_media/{chatId}/{fileName} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 7. Create Firestore Indexes

The app requires a composite index for chat queries. Firebase will prompt you with a link in the debug console on first run — click it to auto-create the index, or create manually:

**Collection:** `chats`  
**Fields:** `participantIds` (Arrays) + `isSecret` (Ascending) + `lastMessageTime` (Descending)

### 8. Run the App

```bash
flutter pub get
flutter run
```

## Running on Device / Emulator

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Run on iOS simulator
flutter run -d iPhone

# Run on Android emulator
flutter run -d emulator-5554
```

## Security Notes

- AES-256 CBC encryption keys are generated per secret chat and stored **only** on the device using `flutter_secure_storage` (iOS Keychain / Android EncryptedSharedPreferences)
- Encrypted messages stored in Firestore are unreadable without the local key
- SSL/TLS enforced via Android `network_security_config.xml`
- No API keys or secrets are hardcoded in source code
- Biometric authentication uses the OS-level biometric APIs (no raw biometric data is accessed)

## Audit Checklist

| Feature | Status |
|---------|--------|
| App runs without crashing | ✅ |
| Login / Signup page | ✅ |
| User authentication | ✅ |
| User profile with photo, username, bio | ✅ |
| QR code generation | ✅ |
| Biometric authentication | ✅ |
| Search users by username | ✅ |
| Add contacts (search + QR scan) | ✅ |
| Send text messages | ✅ |
| Send images | ✅ |
| Send videos | ✅ |
| Read receipts | ✅ |
| Typing indicators | ✅ |
| Edit messages | ✅ |
| Delete messages | ✅ |
| Secret chat (E2E encrypted) | ✅ |
| iOS support | ✅ |
| Android support | ✅ |

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
