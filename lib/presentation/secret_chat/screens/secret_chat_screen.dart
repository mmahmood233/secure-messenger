import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/services/encryption_service.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';
import 'package:secure_messenger/data/repositories/user_repository.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/secret_chat/providers/secret_chat_provider.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';

class SecretChatScreen extends StatefulWidget {
  final ChatModel chat;
  final UserModel otherUser;

  const SecretChatScreen({super.key, required this.chat, required this.otherUser});

  @override
  State<SecretChatScreen> createState() => _SecretChatScreenState();
}

class _SecretChatScreenState extends State<SecretChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late SecretMessageProvider _messageProvider;
  String? _editingMessageId;

  @override
  void initState() {
    super.initState();
    _messageProvider = SecretMessageProvider(
      context.read<ChatRepository>(),
      context.read<EncryptionService>(),
    );
    final uid = context.read<AuthProvider>().currentUser!.uid;
    _messageProvider.initChat(widget.chat.id, uid);
    _messageProvider.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    final uid = context.read<AuthProvider>().currentUser?.uid ?? '';
    _messageProvider.stopListening(widget.chat.id, uid);
    _messageProvider.removeListener(_scrollToBottom);
    _messageProvider.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final uid = context.read<AuthProvider>().currentUser!.uid;

    if (_editingMessageId != null) {
      await _messageProvider.editMessage(
        chatId: widget.chat.id,
        messageId: _editingMessageId!,
        newContent: text,
      );
      setState(() => _editingMessageId = null);
    } else {
      await _messageProvider.sendTextMessage(
        chatId: widget.chat.id,
        senderId: uid,
        content: text,
      );
    }
    _messageController.clear();
    _messageProvider.onTyping(widget.chat.id, uid, false);
  }

  Future<void> _pickAndSendMedia(ImageSource source, String type) async {
    final picker = ImagePicker();
    XFile? picked;
    if (type == AppConstants.imageMessage) {
      picked = await picker.pickImage(source: source, imageQuality: 70);
    } else {
      picked = await picker.pickVideo(source: source);
    }
    if (picked == null) return;
    final uid = context.read<AuthProvider>().currentUser!.uid;
    await _messageProvider.sendMediaMessage(
      chatId: widget.chat.id,
      senderId: uid,
      file: File(picked.path),
      type: type,
    );
  }

  void _showMediaOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppTheme.secretChatColor),
                title: const Text('Photo from Gallery', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendMedia(ImageSource.gallery, AppConstants.imageMessage);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.secretChatColor),
                title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendMedia(ImageSource.camera, AppConstants.imageMessage);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, color: AppTheme.secretChatColor),
                title: const Text('Video from Gallery', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendMedia(ImageSource.gallery, AppConstants.videoMessage);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(MessageModel message, String currentUid) {
    if (message.senderId != currentUid || message.isDeleted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == AppConstants.textMessage)
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppTheme.secretChatColor),
                title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _editingMessageId = message.id;
                    _messageController.text = message.content;
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
              title: const Text('Delete Message', style: TextStyle(color: AppTheme.errorColor)),
              onTap: () {
                Navigator.pop(context);
                _messageProvider.deleteMessage(
                  chatId: widget.chat.id,
                  messageId: message.id,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isOtherUserTyping() {
    return _messageProvider.typingUsers.values.any((v) => v);
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = context.read<AuthProvider>().currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.secretChatColor.withOpacity(0.15),
        leadingWidth: 40,
        title: StreamBuilder<UserModel?>(
          stream: context.read<UserRepository>().watchUser(widget.otherUser.uid),
          builder: (_, snap) {
            final user = snap.data ?? widget.otherUser;
            return Row(
              children: [
                UserAvatar(
                  photoUrl: user.photoUrl,
                  displayName: user.displayName,
                  radius: 18,
                  showOnlineIndicator: true,
                  isOnline: user.isOnline,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(user.displayName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        const Icon(Icons.lock, size: 14, color: AppTheme.secretChatColor),
                      ],
                    ),
                    const Text(
                      'Secret Chat · End-to-End Encrypted',
                      style: TextStyle(fontSize: 11, color: AppTheme.secretChatColor),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: AppTheme.secretChatColor.withOpacity(0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock, size: 14, color: AppTheme.secretChatColor),
                SizedBox(width: 6),
                Text(
                  'Messages are end-to-end encrypted',
                  style: TextStyle(color: AppTheme.secretChatColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _messageProvider,
              builder: (_, __) {
                final messages = _messageProvider.messages;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length + (_isOtherUserTyping() ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == messages.length) {
                      return const _SecretTypingIndicator();
                    }
                    final msg = messages[i];
                    final isMe = msg.senderId == currentUid;
                    return _SecretMessageBubble(
                      message: msg,
                      isMe: isMe,
                      onLongPress: () => _showMessageOptions(msg, currentUid),
                    );
                  },
                );
              },
            ),
          ),
          if (_editingMessageId != null)
            Container(
              color: AppTheme.secretChatColor.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: AppTheme.secretChatColor, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Editing message',
                        style: TextStyle(color: AppTheme.secretChatColor, fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() => _editingMessageId = null);
                      _messageController.clear();
                    },
                    child: const Icon(Icons.close, color: AppTheme.subtitleColor, size: 18),
                  ),
                ],
              ),
            ),
          _SecretMessageInput(
            controller: _messageController,
            onSend: _sendMessage,
            onAttach: _showMediaOptions,
            onTyping: (typing) {
              _messageProvider.onTyping(widget.chat.id, currentUid, typing);
            },
            isEditing: _editingMessageId != null,
          ),
        ],
      ),
    );
  }
}

class _SecretMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback onLongPress;

  const _SecretMessageBubble({
    required this.message,
    required this.isMe,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe
                ? AppTheme.secretChatColor.withOpacity(0.85)
                : AppTheme.receivedBubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.isDeleted)
                const Text(
                  'This message was deleted',
                  style: TextStyle(
                    color: AppTheme.subtitleColor,
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                )
              else if (message.type == AppConstants.imageMessage && message.mediaUrl != null)
                _SecretMediaContent(url: message.mediaUrl!, type: AppConstants.imageMessage)
              else if (message.type == AppConstants.videoMessage && message.mediaUrl != null)
                _SecretMediaContent(url: message.mediaUrl!, type: AppConstants.videoMessage)
              else
                Text(
                  message.content,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 10, color: AppTheme.subtitleColor),
                  const SizedBox(width: 3),
                  if (message.isEdited && !message.isDeleted)
                    const Text(
                      'edited · ',
                      style: TextStyle(color: AppTheme.subtitleColor, fontSize: 10),
                    ),
                  Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 11),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _StatusIcon(status: message.status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case AppConstants.statusRead:
        return const Icon(Icons.done_all, size: 14, color: AppTheme.secondaryColor);
      case AppConstants.statusDelivered:
        return const Icon(Icons.done_all, size: 14, color: AppTheme.subtitleColor);
      default:
        return const Icon(Icons.done, size: 14, color: AppTheme.subtitleColor);
    }
  }
}

class _SecretMediaContent extends StatelessWidget {
  final String url;
  final String type;
  const _SecretMediaContent({required this.url, required this.type});

  @override
  Widget build(BuildContext context) {
    if (type == AppConstants.imageMessage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              width: 200,
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          },
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening video...')),
        );
      },
      child: Container(
        width: 200,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
        ),
      ),
    );
  }
}

class _SecretTypingIndicator extends StatelessWidget {
  const _SecretTypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.receivedBubbleColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0),
            const SizedBox(width: 4),
            _Dot(delay: 200),
            const SizedBox(width: 4),
            _Dot(delay: 400),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppTheme.subtitleColor,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _SecretMessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final void Function(bool) onTyping;
  final bool isEditing;

  const _SecretMessageInput({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onTyping,
    required this.isEditing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          top: BorderSide(color: AppTheme.secretChatColor.withOpacity(0.3)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, color: AppTheme.subtitleColor),
              onPressed: onAttach,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 5,
                minLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: isEditing ? 'Edit message...' : 'Secret message...',
                  hintStyle: const TextStyle(color: AppTheme.subtitleColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppTheme.cardColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onChanged: (text) => onTyping(text.isNotEmpty),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppTheme.secretChatColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
