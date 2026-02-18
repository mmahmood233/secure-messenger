import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/chat/screens/chat_screen.dart';
import 'package:secure_messenger/presentation/contacts/providers/contacts_provider.dart';
import 'package:secure_messenger/presentation/profile/screens/view_profile_screen.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    context.read<ContactsProvider>().searchUsers(query);
  }

  Future<void> _openChat(UserModel user) async {
    final auth = context.read<AuthProvider>();
    final chatRepo = context.read<ChatRepository>();
    final chat = await chatRepo.getOrCreateChat(
      auth.currentUser!.uid,
      user.uid,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chat: chat, otherUser: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = context.read<AuthProvider>().currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search by username...',
            hintStyle: TextStyle(color: AppTheme.subtitleColor),
            border: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          onChanged: _onSearch,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                context.read<ContactsProvider>().clearSearch();
                setState(() {});
              },
            ),
        ],
      ),
      body: Consumer<ContactsProvider>(
        builder: (_, contacts, __) {
          if (_controller.text.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: AppTheme.subtitleColor.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Search for users by username',
                    style: TextStyle(color: AppTheme.subtitleColor),
                  ),
                ],
              ),
            );
          }

          if (contacts.isSearching) {
            return const Center(child: CircularProgressIndicator());
          }

          final results = contacts.searchResults
              .where((u) => u.uid != currentUid)
              .toList();

          if (results.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_search,
                    size: 64,
                    color: AppTheme.subtitleColor.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No users found for "${_controller.text}"',
                    style: const TextStyle(color: AppTheme.subtitleColor),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (_, i) {
              final user = results[i];
              return ListTile(
                onTap: () => _openChat(user),
                onLongPress: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ViewProfileScreen(user: user),
                  ),
                ),
                leading: UserAvatar(
                  photoUrl: user.photoUrl,
                  displayName: user.displayName,
                  showOnlineIndicator: true,
                  isOnline: user.isOnline,
                ),
                title: Text(
                  user.displayName,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '@${user.username}',
                  style: const TextStyle(
                      color: AppTheme.subtitleColor, fontSize: 13),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline,
                      color: AppTheme.primaryColor),
                  onPressed: () => _openChat(user),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
