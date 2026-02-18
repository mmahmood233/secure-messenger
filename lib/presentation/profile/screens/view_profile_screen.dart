import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/chat/screens/chat_screen.dart';
import 'package:secure_messenger/presentation/contacts/providers/contacts_provider.dart';
import 'package:secure_messenger/presentation/secret_chat/screens/secret_chat_screen.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';

class ViewProfileScreen extends StatefulWidget {
  final UserModel user;

  const ViewProfileScreen({super.key, required this.user});

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  bool _isContact = false;
  bool _checkingContact = true;

  @override
  void initState() {
    super.initState();
    _checkContact();
  }

  Future<void> _checkContact() async {
    final currentUid = context.read<AuthProvider>().currentUser?.uid;
    if (currentUid == null) return;
    final isContact = await context
        .read<ContactsProvider>()
        .isContact(currentUid, widget.user.uid);
    if (mounted) {
      setState(() {
        _isContact = isContact;
        _checkingContact = false;
      });
    }
  }

  Future<void> _addContact() async {
    final currentUid = context.read<AuthProvider>().currentUser?.uid;
    if (currentUid == null) return;
    final success = await context
        .read<ContactsProvider>()
        .addContact(currentUid, widget.user.uid);
    if (success && mounted) {
      setState(() => _isContact = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.user.displayName} added to contacts')),
      );
    }
  }

  Future<void> _openChat() async {
    final auth = context.read<AuthProvider>();
    final chatRepo = context.read<ChatRepository>();
    final chat = await chatRepo.getOrCreateChat(
      auth.currentUser!.uid,
      widget.user.uid,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chat: chat, otherUser: widget.user),
      ),
    );
  }

  Future<void> _openSecretChat() async {
    final auth = context.read<AuthProvider>();
    final chatRepo = context.read<ChatRepository>();
    final chat = await chatRepo.getOrCreateChat(
      auth.currentUser!.uid,
      widget.user.uid,
      isSecret: true,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecretChatScreen(chat: chat, otherUser: widget.user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final currentUid = context.read<AuthProvider>().currentUser?.uid;
    final isSelf = currentUid == user.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            UserAvatar(
              photoUrl: user.photoUrl,
              displayName: user.displayName,
              radius: 52,
              showOnlineIndicator: true,
              isOnline: user.isOnline,
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 4),
            Text(
              user.isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                color: user.isOnline
                    ? AppTheme.secondaryColor
                    : AppTheme.subtitleColor,
                fontSize: 13,
              ),
            ),
            if (user.bio != null && user.bio!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                user.bio!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.subtitleColor, fontSize: 14),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: 'securemessenger://user/${user.uid}',
                version: QrVersions.auto,
                size: 160,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            if (!isSelf) ...[
              if (!_checkingContact && !_isContact)
                _ActionButton(
                  icon: Icons.person_add_outlined,
                  label: 'Add Contact',
                  onTap: _addContact,
                ),
              if (!_checkingContact && !_isContact)
                const SizedBox(height: 12),
              _ActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'Send Message',
                onTap: _openChat,
              ),
              const SizedBox(height: 12),
              _ActionButton(
                icon: Icons.lock_outline,
                label: 'Start Secret Chat',
                color: AppTheme.secretChatColor,
                onTap: _openSecretChat,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryColor;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
