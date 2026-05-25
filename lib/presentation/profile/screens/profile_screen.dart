import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/profile/providers/profile_provider.dart';
import 'package:secure_messenger/presentation/widgets/app_text_field.dart';
import 'package:secure_messenger/presentation/widgets/app_button.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  late TextEditingController _phoneController;
  bool _isEditing = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _displayNameController =
        TextEditingController(text: user?.displayName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final profile = context.read<ProfileProvider>();
    final uid = auth.currentUser!.uid;

    if (_selectedImage != null) {
      final url = await profile.uploadProfilePhoto(uid, _selectedImage!);
      if (url != null) {
        auth.updateCurrentUser(auth.currentUser!.copyWith(photoUrl: url));
      }
    }

    final success = await profile.updateProfile(
      uid: uid,
      displayName: _displayNameController.text.trim(),
      username: _usernameController.text.trim(),
      bio: _bioController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
    );

    if (success && mounted) {
      auth.updateCurrentUser(auth.currentUser!.copyWith(
        displayName: _displayNameController.text.trim(),
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      ));
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    }
  }

  void _showQrCode(UserModel user) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'My QR Code',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan to add @${user.username}',
                style: const TextStyle(color: AppTheme.subtitleColor),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: 'securemessenger://user/${user.uid}',
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '@${user.username}',
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                user.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBiometricSettings() {
    final auth = context.read<AuthProvider>();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Biometric Login',
            style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (ctx, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enable biometric authentication to unlock the app and sign in on this device.',
                  style: TextStyle(color: AppTheme.subtitleColor),
                ),
                const SizedBox(height: 16),
                if (auth.biometricEnabled)
                  SwitchListTile(
                    title: const Text('Enabled',
                        style: TextStyle(color: Colors.white)),
                    value: true,
                    onChanged: auth.biometricAvailable
                        ? (val) async {
                            if (!val) {
                              await auth.disableBiometricLogin();
                              setState(() {});
                            }
                          }
                        : null,
                    activeColor: AppTheme.primaryColor,
                  )
                else if (auth.biometricAvailable) ...[
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => obscurePassword = !obscurePassword);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Enable Biometrics'),
                      onPressed: () async {
                        final success = await auth.enableBiometricLogin(
                          passwordController.text,
                        );
                        if (success) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ],
                if (!auth.biometricAvailable)
                  const Text(
                    'Biometric authentication is not available on this device.',
                    style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              passwordController.dispose();
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, ProfileProvider>(
      builder: (context, auth, profile, _) {
        final user = auth.currentUser;
        if (user == null) return const SizedBox.shrink();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            actions: [
              if (!_isEditing)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() => _isEditing = true),
                )
              else
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  child: const Text('Cancel'),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isEditing ? _pickImage : null,
                    child: Stack(
                      children: [
                        _selectedImage != null
                            ? CircleAvatar(
                                radius: 52,
                                backgroundImage: FileImage(_selectedImage!),
                              )
                            : UserAvatar(
                                photoUrl: user.photoUrl,
                                displayName: user.displayName,
                                radius: 52,
                              ),
                        if (_isEditing)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.backgroundColor,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_isEditing) ...[
                    Text(
                      user.displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 15,
                      ),
                    ),
                    if (user.bio != null && user.bio!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        user.bio!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.subtitleColor, fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _InfoCard(
                      items: [
                        _InfoItem(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: user.email),
                        if (user.phoneNumber != null &&
                            user.phoneNumber!.isNotEmpty)
                          _InfoItem(
                              icon: Icons.phone_outlined,
                              label: 'Phone',
                              value: user.phoneNumber!),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.qr_code_rounded,
                            label: 'My QR Code',
                            onTap: () => _showQrCode(user),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.fingerprint,
                            label: 'Biometric',
                            onTap: _showBiometricSettings,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ActionCard(
                      icon: Icons.logout,
                      label: 'Sign Out',
                      color: AppTheme.errorColor,
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: AppTheme.cardColor,
                            title: const Text('Sign Out',
                                style: TextStyle(color: Colors.white)),
                            content: const Text(
                              'Are you sure you want to sign out?',
                              style: TextStyle(color: AppTheme.subtitleColor),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Sign Out',
                                    style:
                                        TextStyle(color: AppTheme.errorColor)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          await context.read<AuthProvider>().signOut();
                        }
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                    AppTextField(
                      controller: _displayNameController,
                      label: 'Display Name',
                      prefixIcon: Icons.person_outline,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _usernameController,
                      label: 'Username',
                      prefixIcon: Icons.alternate_email,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (v.trim().length < 3) return 'At least 3 characters';
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v.trim())) {
                          return 'Only letters, numbers, underscores';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _bioController,
                      label: 'Bio',
                      hint: 'Tell others about yourself',
                      prefixIcon: Icons.info_outline,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      hint: 'Optional',
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      label: 'Save Changes',
                      isLoading: profile.status == ProfileStatus.loading,
                      onPressed: _saveProfile,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<_InfoItem> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final isLast = entry.key == items.length - 1;
          return Column(
            children: [
              ListTile(
                leading: Icon(entry.value.icon,
                    color: AppTheme.primaryColor, size: 20),
                title: Text(entry.value.label,
                    style: const TextStyle(
                        color: AppTheme.subtitleColor, fontSize: 12)),
                subtitle: Text(entry.value.value,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              if (!isLast)
                const Divider(
                    height: 1, color: AppTheme.dividerColor, indent: 56),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  const _InfoItem(
      {required this.icon, required this.label, required this.value});
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: c, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
