import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

// TODO: Replace these values with your actual Firebase project configuration.
// Run `flutterfire configure` after creating a Firebase project to auto-generate this file.
// Steps:
//   1. Go to https://console.firebase.google.com
//   2. Create a project named "secure-messenger"
//   3. Add Android app (package: com.securemessenger.secure_messenger)
//   4. Add iOS app (bundle ID: com.securemessenger.secureMessenger)
//   5. Run: dart pub global activate flutterfire_cli
//   6. Run: flutterfire configure
// Then replace the placeholder values below with the generated ones.

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not supported.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // REPLACE with your Android Firebase config
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  // REPLACE with your iOS Firebase config
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.securemessenger.secureMessenger',
  );
}
