import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:secure_messenger/core/utils/date_formatter.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/user_repository.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/chat/providers/chat_provider.dart';
import 'package:secure_messenger/presentation/chat/screens/chat_screen.dart';
import 'package:secure_messenger/presentation/contacts/screens/contacts_screen.dart';
import 'package:secure_messenger/presentation/contacts/screens/search_screen.dart';
import 'package:secure_messenger/presentation/profile/screens/profile_screen.dart';
import 'package:secure_messenger/presentation/secret_chat/screens/secret_chat_screen.dart';
import 'package:secure_messenger/presentation/widgets/offline_banner.dart';
import 'package:secure_messenger/presentation/widgets/app_logo.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    _ChatsTab(),
    ContactsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AuthProvider>().currentUser?.uid;
      if (uid != null) {
        context.read<ChatProvider>().startListening(uid);
        _setOnlineStatus(uid, true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = context.read<AuthProvider>().currentUser?.uid;
    if (uid == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _setOnlineStatus(uid, true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        _setOnlineStatus(uid, false);
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _setOnlineStatus(String uid, bool isOnline) {
    context
        .read<UserRepository>()
        .updateOnlineStatus(uid, isOnline)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: AppTheme.primaryColor),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: AppTheme.primaryColor),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppTheme.primaryColor),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactsScreen()),
              ),
              child: const Icon(Icons.chat_rounded),
            )
          : null,
    );
  }
}

class _ChatsTab extends StatelessWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const AppLogo(showWordmark: true, size: 34),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(48),
            child: TabBar(
              tabs: [
                Tab(text: 'Chats'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock,
                          size: 14, color: AppTheme.secretChatColor),
                      SizedBox(width: 4),
                      Text('Secret'),
                    ],
                  ),
                ),
              ],
              indicatorColor: AppTheme.primaryColor,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.subtitleColor,
              labelStyle: TextStyle(fontWeight: FontWeight.w700),
              unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search users',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            _ChatList(isSecret: false),
            _ChatList(isSecret: true),
          ],
        ),
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  final bool isSecret;
  const _ChatList({required this.isSecret});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final chats = isSecret ? chatProvider.secretChats : chatProvider.chats;

        if (chatProvider.status == ChatListStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSecret ? Icons.lock_outline : Icons.chat_bubble_outline,
                  size: 64,
                  color: isSecret
                      ? AppTheme.secretChatColor.withOpacity(0.4)
                      : AppTheme.subtitleColor.withOpacity(0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  isSecret ? 'No secret chats yet' : 'No chats yet',
                  style: const TextStyle(
                      color: AppTheme.subtitleColor, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  isSecret
                      ? 'Start an encrypted conversation'
                      : 'Find contacts and start chatting',
                  style: const TextStyle(
                      color: AppTheme.subtitleColor, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(top: 6, bottom: 88),
          itemCount: chats.length,
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            indent: 84,
            color: AppTheme.dividerColor,
          ),
          itemBuilder: (_, i) => _ChatTile(chat: chats[i], isSecret: isSecret),
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatModel chat;
  final bool isSecret;

  const _ChatTile({required this.chat, required this.isSecret});

  @override
  Widget build(BuildContext context) {
    final currentUid = context.read<AuthProvider>().currentUser!.uid;
    final otherUid = chat.getOtherParticipantId(currentUid);

    return FutureBuilder<UserModel?>(
      future: context.read<UserRepository>().getUserById(otherUid),
      builder: (_, snap) {
        final user = snap.data;
        if (user == null) return const SizedBox.shrink();

        final unread = chat.unreadCount[currentUid] ?? 0;

        return InkWell(
          onTap: () {
            if (isSecret) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SecretChatScreen(chat: chat, otherUser: user),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(chat: chat, otherUser: user),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Stack(
                  children: [
                    UserAvatar(
                      photoUrl: user.photoUrl,
                      displayName: user.displayName,
                      radius: 27,
                      showOnlineIndicator: true,
                      isOnline: user.isOnline,
                    ),
                    if (isSecret)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppTheme.secretChatColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock,
                            size: 9,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.displayName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: unread > 0
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (chat.lastMessageTime != null)
                            Text(
                              _formatTime(chat.lastMessageTime!),
                              style: TextStyle(
                                color: unread > 0
                                    ? AppTheme.primaryColor
                                    : AppTheme.subtitleColor,
                                fontSize: 12,
                                fontWeight: unread > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (isSecret && chat.lastMessage != null) ...[
                            const Icon(
                              Icons.lock,
                              size: 13,
                              color: AppTheme.secretChatColor,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              isSecret && chat.lastMessage != null
                                  ? 'Encrypted message'
                                  : (chat.lastMessage ?? 'No messages yet'),
                              style: TextStyle(
                                color: unread > 0
                                    ? Colors.white70
                                    : AppTheme.subtitleColor,
                                fontSize: 14,
                                fontWeight: unread > 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread > 0)
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 22,
                                minHeight: 22,
                              ),
                              alignment: Alignment.center,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: isSecret
                                    ? AppTheme.secretChatColor
                                    : AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : unread.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) => DateFormatter.formatMessageTime(time);
}
