import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:secure_messenger/core/services/biometric_service.dart';
import 'package:secure_messenger/core/services/encryption_service.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/repositories/auth_repository.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';
import 'package:secure_messenger/data/repositories/user_repository.dart';
import 'package:secure_messenger/firebase_options.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/auth/screens/login_screen.dart';
import 'package:secure_messenger/presentation/chat/providers/chat_provider.dart';
import 'package:secure_messenger/presentation/contacts/providers/contacts_provider.dart';
import 'package:secure_messenger/presentation/home/screens/home_screen.dart';
import 'package:secure_messenger/presentation/profile/providers/profile_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SecureMessengerApp());
}

class SecureMessengerApp extends StatelessWidget {
  const SecureMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );

    final encryptionService = EncryptionService(secureStorage);
    final biometricService = BiometricService(LocalAuthentication(), secureStorage);
    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;
    final auth = FirebaseAuth.instance;

    final authRepo = AuthRepository(auth, firestore);
    final userRepo = UserRepository(firestore, storage);
    final chatRepo = ChatRepository(firestore, storage);

    return MultiProvider(
      providers: [
        Provider<FlutterSecureStorage>.value(value: secureStorage),
        Provider<EncryptionService>.value(value: encryptionService),
        Provider<BiometricService>.value(value: biometricService),
        Provider<AuthRepository>.value(value: authRepo),
        Provider<UserRepository>.value(value: userRepo),
        Provider<ChatRepository>.value(value: chatRepo),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authRepo, biometricService),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileProvider(userRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => ContactsProvider(userRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(chatRepo),
        ),
      ],
      child: MaterialApp(
        title: 'SecureMessenger',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _AppRouter(),
      ),
    );
  }
}

class _AppRouter extends StatelessWidget {
  const _AppRouter();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final status = auth.status;
        switch (status) {
          case AuthStatus.initial:
          case AuthStatus.loading:
            return const _SplashScreen();
          case AuthStatus.authenticated:
            return const HomeScreen();
          case AuthStatus.unauthenticated:
          case AuthStatus.error:
            return const LoginScreen();
        }
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 64, color: AppTheme.primaryColor),
            SizedBox(height: 16),
            Text(
              'SecureMessenger',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 32),
            CircularProgressIndicator(color: AppTheme.primaryColor),
          ],
        ),
      ),
    );
  }
}
