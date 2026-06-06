import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';
import 'package:secure_messenger/data/repositories/user_repository.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/chat/providers/chat_provider.dart';
import 'package:secure_messenger/core/utils/date_formatter.dart';
import 'package:secure_messenger/presentation/widgets/image_viewer_screen.dart';
import 'package:secure_messenger/presentation/widgets/media_send_preview_screen.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';
import 'package:secure_messenger/presentation/widgets/video_player_screen.dart';

class ChatScreen extends StatefulWidget {
  final ChatModel chat;
  final UserModel otherUser;

  const ChatScreen({super.key, required this.chat, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late MessageProvider _messageProvider;
  String? _editingMessageId;

  @override
  void initState() {
    super.initState();
    _messageProvider = MessageProvider(context.read());
    final uid = context.read<AuthProvider>().currentUser!.uid;
    _messageProvider.startListening(widget.chat.id, uid);
    _messageProvider.addListener(_onProviderUpdate);
  }

  void _onProviderUpdate() {
    _scrollToBottom();
    if (_messageProvider.errorMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageProvider.errorMessage!),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _messageProvider.clearError();
    }
  }

  @override
  void dispose() {
    final uid = context.read<AuthProvider>().currentUser?.uid ?? '';
    _messageProvider.stopListening(widget.chat.id, uid);
    _messageProvider.removeListener(_onProviderUpdate);
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
      _messageController.clear();
      _messageProvider.onTyping(widget.chat.id, uid, false);
      await _messageProvider.sendTextMessage(
        chatId: widget.chat.id,
        senderId: uid,
        content: text,
      );
    }
  }

  Future<void> _pickAndSendMedia(ImageSource source, String type) async {
    final uid = context.read<AuthProvider>().currentUser!.uid;
    final picker = ImagePicker();
    XFile? picked;
    if (type == AppConstants.imageMessage) {
      picked = await picker.pickImage(source: source, imageQuality: 70);
    } else {
      picked = await picker.pickVideo(source: source);
    }
    if (picked == null) return;
    await _previewAndSendMedia(
      uid: uid,
      file: File(picked.path),
      type: type,
    );
  }

  Future<void> _previewAndSendMedia({
    required String uid,
    required File file,
    required String type,
  }) async {
    final shouldSend = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaSendPreviewScreen(
          file: file,
          type: type,
          accentColor: AppTheme.primaryColor,
        ),
      ),
    );
    if (shouldSend != true || !mounted) return;
    await _messageProvider.sendMediaMessage(
      chatId: widget.chat.id,
      senderId: uid,
      file: file,
      type: type,
    );
  }

  Future<void> _pickAndSendImages() async {
    final uid = context.read<AuthProvider>().currentUser!.uid;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 70);
    if (picked.isEmpty) return;

    for (final image in picked) {
      if (!mounted) return;
      await _previewAndSendMedia(
        uid: uid,
        file: File(image.path),
        type: AppConstants.imageMessage,
      );
    }
  }

  Future<void> _pickAndSendAudio() async {
    final uid = context.read<AuthProvider>().currentUser!.uid;
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = picked?.files.single.path;
    if (path == null) return;
    await _previewAndSendMedia(
      uid: uid,
      file: File(path),
      type: AppConstants.audioMessage,
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
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Photos from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImages();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Take Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendMedia(
                      ImageSource.camera, AppConstants.imageMessage);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Video from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendMedia(
                      ImageSource.gallery, AppConstants.videoMessage);
                },
              ),
              ListTile(
                leading: const Icon(Icons.audiotrack_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Audio File',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendAudio();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(MessageModel message, String currentUid) {
    if (message.isDeleted) return;
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
                leading: const Icon(Icons.copy_outlined,
                    color: AppTheme.subtitleColor),
                title: const Text('Copy Text',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            if (message.senderId == currentUid &&
                message.type == AppConstants.textMessage)
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Edit Message',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _editingMessageId = message.id;
                    _messageController.text = message.content;
                  });
                },
              ),
            if (message.senderId == currentUid)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppTheme.errorColor),
                title: const Text('Delete Message',
                    style: TextStyle(color: AppTheme.errorColor)),
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

  List<Widget> _buildItemList(List<MessageModel> messages, bool showTyping) {
    final items = <Widget>[];
    DateTime? lastDate;
    for (final msg in messages) {
      final msgDate = DateTime(
        msg.timestamp.year,
        msg.timestamp.month,
        msg.timestamp.day,
      );
      if (lastDate == null || msgDate != lastDate) {
        items.add(_DateSeparator(
          key: ValueKey('date_${msgDate.toIso8601String()}'),
          label: DateFormatter.formatDateSeparator(msg.timestamp),
        ));
        lastDate = msgDate;
      }
      final isMe =
          msg.senderId == context.read<AuthProvider>().currentUser!.uid;
      items.add(_MessageBubble(
        key: ValueKey('message_${msg.id}'),
        message: msg,
        isMe: isMe,
        onLongPress: () => _showMessageOptions(
          msg,
          context.read<AuthProvider>().currentUser!.uid,
        ),
      ));
    }
    if (showTyping) {
      items.add(const _TypingIndicator(key: ValueKey('typing_indicator')));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = context.read<AuthProvider>().currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 36,
        title: StreamBuilder<UserModel?>(
          stream:
              context.read<UserRepository>().watchUser(widget.otherUser.uid),
          builder: (_, snap) {
            final user = snap.data ?? widget.otherUser;
            return Row(
              children: [
                UserAvatar(
                  photoUrl: user.photoUrl,
                  displayName: user.displayName,
                  radius: 20,
                  showOnlineIndicator: true,
                  isOnline: user.isOnline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        user.isOnline
                            ? 'online'
                            : user.lastSeen != null
                                ? 'last seen ${timeago.format(user.lastSeen!)}'
                                : 'offline',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: user.isOnline
                              ? AppTheme.secondaryColor
                              : AppTheme.subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _messageProvider,
              builder: (_, __) {
                final messages = _messageProvider.messages;
                final items = _buildItemList(messages, _isOtherUserTyping());
                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) => items[i],
                );
              },
            ),
          ),
          if (_editingMessageId != null)
            Container(
              color: AppTheme.primaryColor.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.edit,
                      color: AppTheme.primaryColor, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Editing message',
                        style: TextStyle(
                            color: AppTheme.primaryColor, fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() => _editingMessageId = null);
                      _messageController.clear();
                    },
                    child: const Icon(Icons.close,
                        color: AppTheme.subtitleColor, size: 18),
                  ),
                ],
              ),
            ),
          _MessageInput(
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

class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback onLongPress;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onLongPress,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _showTimestamp = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => setState(() => _showTimestamp = !_showTimestamp),
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.of(context).size.width * 0.78)
                    .clamp(180.0, 420.0),
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.sentBubbleColor
                    : AppTheme.receivedBubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 3),
                  bottomRight: Radius.circular(isMe ? 3 : 16),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
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
                  else if (message.type == AppConstants.textMessage)
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.28,
                      ),
                    )
                  else if (message.mediaUrl != null)
                    _MediaContent(
                      key: ValueKey('media_${message.id}_${message.mediaUrl}'),
                      url: message.mediaUrl!,
                      type: message.type,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(message.timestamp),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
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
            if (_showTimestamp)
              Padding(
                padding:
                    const EdgeInsets.only(top: 2, bottom: 4, left: 4, right: 4),
                child: Text(
                  DateFormatter.formatFullDate(message.timestamp),
                  style: const TextStyle(
                    color: AppTheme.subtitleColor,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
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
        return const Icon(Icons.done_all,
            size: 14, color: AppTheme.secondaryColor);
      case AppConstants.statusDelivered:
        return const Icon(Icons.done_all,
            size: 14, color: AppTheme.subtitleColor);
      default:
        return const Icon(Icons.done, size: 14, color: AppTheme.subtitleColor);
    }
  }
}

class _MediaContent extends StatefulWidget {
  final String url;
  final String type;

  const _MediaContent({
    super.key,
    required this.url,
    required this.type,
  });

  @override
  State<_MediaContent> createState() => _MediaContentState();
}

class _MediaContentState extends State<_MediaContent>
    with AutomaticKeepAliveClientMixin {
  late Future<String> _signedUrlFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _signedUrlFuture = _createSignedUrl();
  }

  @override
  void didUpdateWidget(covariant _MediaContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _signedUrlFuture = _createSignedUrl();
    }
  }

  Future<String> _createSignedUrl() {
    return context.read<ChatRepository>().createSignedMediaUrl(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.type == AppConstants.imageMessage) {
      return FutureBuilder<String>(
        future: _signedUrlFuture,
        builder: (context, snapshot) {
          final signedUrl = snapshot.data;
          if (signedUrl == null) {
            return const SizedBox(
              width: 200,
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ImageViewerScreen(imageUrl: signedUrl, heroTag: widget.url),
              ),
            ),
            child: Hero(
              tag: widget.url,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  signedUrl,
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
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, color: Colors.white),
                ),
              ),
            ),
          );
        },
      );
    }
    if (widget.type == AppConstants.audioMessage) {
      return FutureBuilder<String>(
        future: _signedUrlFuture,
        builder: (context, snapshot) {
          final signedUrl = snapshot.data;
          if (signedUrl == null) {
            return const SizedBox(
              width: 220,
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    VideoPlayerScreen(videoUrl: signedUrl, isAudio: true),
              ),
            ),
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 32),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Audio message',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return FutureBuilder<String>(
      future: _signedUrlFuture,
      builder: (context, snapshot) {
        final signedUrl = snapshot.data;
        if (signedUrl == null) {
          return const SizedBox(
            width: 200,
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(videoUrl: signedUrl),
            ),
          ),
          child: Container(
            width: 200,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child:
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
            ),
          ),
        );
      },
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({super.key});

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

class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.subtitleColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
        ],
      ),
    );
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final void Function(bool) onTyping;
  final bool isEditing;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onTyping,
    required this.isEditing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(top: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppTheme.inputColor,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.attach_file,
                    color: AppTheme.subtitleColor, size: 21),
                onPressed: onAttach,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 5,
                minLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.25,
                ),
                decoration: InputDecoration(
                  hintText: isEditing ? 'Edit message...' : 'Type a message...',
                  hintStyle: const TextStyle(color: AppTheme.subtitleColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppTheme.inputColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
