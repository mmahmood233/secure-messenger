import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/chat/screens/chat_screen.dart';
import 'package:secure_messenger/presentation/contacts/providers/contacts_provider.dart';
import 'package:secure_messenger/presentation/profile/screens/view_profile_screen.dart';
import 'package:secure_messenger/presentation/secret_chat/screens/secret_chat_screen.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AuthProvider>().currentUser?.uid;
      if (uid != null) {
        context.read<ContactsProvider>().loadContacts(uid);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChat(UserModel contact) async {
    final auth = context.read<AuthProvider>();
    final chatRepo = context.read<ChatRepository>();
    final chat = await chatRepo.getOrCreateChat(
      auth.currentUser!.uid,
      contact.uid,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chat: chat, otherUser: contact),
      ),
    );
  }

  void _showQrScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search by username...',
                  hintStyle: TextStyle(color: AppTheme.subtitleColor),
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (q) =>
                    context.read<ContactsProvider>().searchUsers(q),
              )
            : const Text('Contacts'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (!_showSearch) {
                _searchController.clear();
                context.read<ContactsProvider>().clearSearch();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _showQrScanner,
          ),
        ],
      ),
      body: Consumer<ContactsProvider>(
        builder: (context, contacts, _) {
          if (_showSearch && _searchController.text.isNotEmpty) {
            return _SearchResults(
              results: contacts.searchResults,
              isSearching: contacts.isSearching,
              onTap: _openChat,
            );
          }

          if (contacts.status == ContactsStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (contacts.contacts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline,
                      size: 64, color: AppTheme.subtitleColor.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text(
                    'No contacts yet',
                    style: TextStyle(color: AppTheme.subtitleColor, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Search for users to add them',
                    style: TextStyle(color: AppTheme.subtitleColor, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: contacts.contacts.length,
            itemBuilder: (_, i) {
              final contact = contacts.contacts[i];
              return _ContactTile(contact: contact, onTap: () => _openChat(contact));
            },
          );
        },
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final UserModel contact;
  final VoidCallback onTap;

  const _ContactTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      onLongPress: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViewProfileScreen(user: contact),
        ),
      ),
      leading: UserAvatar(
        photoUrl: contact.photoUrl,
        displayName: contact.displayName,
        showOnlineIndicator: true,
        isOnline: contact.isOnline,
      ),
      title: Text(contact.displayName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text('@${contact.username}',
          style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.subtitleColor),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<UserModel> results;
  final bool isSearching;
  final void Function(UserModel) onTap;

  const _SearchResults({
    required this.results,
    required this.isSearching,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      return const Center(
        child: Text('No users found', style: TextStyle(color: AppTheme.subtitleColor)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final user = results[i];
        final currentUid = context.read<AuthProvider>().currentUser?.uid;
        if (user.uid == currentUid) return const SizedBox.shrink();
        return ListTile(
          onTap: () => _showAddContact(context, user),
          leading: UserAvatar(
            photoUrl: user.photoUrl,
            displayName: user.displayName,
          ),
          title: Text(user.displayName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: Text('@${user.username}',
              style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
          trailing: const Icon(Icons.person_add_outlined, color: AppTheme.primaryColor),
        );
      },
    );
  }

  void _showAddContact(BuildContext context, UserModel user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddContactSheet(user: user, onChat: () => onTap(user)),
    );
  }
}

class _AddContactSheet extends StatelessWidget {
  final UserModel user;
  final VoidCallback onChat;

  const _AddContactSheet({required this.user, required this.onChat});

  void _openSecretChat(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final chatRepo = context.read<ChatRepository>();
    final chat = await chatRepo.getOrCreateChat(
      auth.currentUser!.uid,
      user.uid,
      isSecret: true,
    );
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecretChatScreen(chat: chat, otherUser: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(photoUrl: user.photoUrl, displayName: user.displayName, radius: 36),
          const SizedBox(height: 12),
          Text(user.displayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          Text('@${user.username}',
              style: const TextStyle(color: AppTheme.primaryColor, fontSize: 14)),
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(user.bio!, style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final auth = context.read<AuthProvider>();
                    final contacts = context.read<ContactsProvider>();
                    await contacts.addContact(auth.currentUser!.uid, user.uid);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${user.displayName} added to contacts')),
                      );
                    }
                  },
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Add Contact'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onChat();
                  },
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openSecretChat(context);
              },
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Start Secret Chat'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secretChatColor,
                side: const BorderSide(color: AppTheme.secretChatColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        onDetect: (capture) async {
          if (_scanned) return;
          final barcode = capture.barcodes.firstOrNull;
          if (barcode?.rawValue == null) return;

          final raw = barcode!.rawValue!;
          if (!raw.startsWith('securemessenger://user/')) return;

          _scanned = true;
          final uid = raw.replaceFirst('securemessenger://user/', '');

          final contacts = context.read<ContactsProvider>();
          final user = await contacts.getUserByUid(uid);

          if (!mounted) return;

          if (user == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('User not found')),
            );
            setState(() => _scanned = false);
            return;
          }

          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            backgroundColor: AppTheme.cardColor,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => _AddContactSheet(
              user: user,
              onChat: () {
                final auth = context.read<AuthProvider>();
                final chatRepo = context.read<ChatRepository>();
                chatRepo
                    .getOrCreateChat(auth.currentUser!.uid, user.uid)
                    .then((chat) {
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(chat: chat, otherUser: user),
                      ),
                    );
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }
}
