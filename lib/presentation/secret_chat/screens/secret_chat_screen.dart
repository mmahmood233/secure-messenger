// Secret chat screen.
// UI for encrypted one-on-one conversations with text/media, typing indicators,
// read receipts, edit, and delete.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:secure_messenger/core/constants/app_constants.dart';
import 'package:secure_messenger/core/utils/date_formatter.dart';
import 'package:secure_messenger/core/services/encryption_service.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';
import 'package:secure_messenger/data/models/chat_model.dart';
import 'package:secure_messenger/data/models/message_model.dart';
import 'package:secure_messenger/data/models/user_model.dart';
import 'package:secure_messenger/data/repositories/chat_repository.dart';
import 'package:secure_messenger/data/repositories/user_repository.dart';
import 'package:secure_messenger/presentation/auth/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/secret_chat/providers/secret_chat_provider.dart';
import 'package:secure_messenger/presentation/widgets/image_viewer_screen.dart';
import 'package:secure_messenger/presentation/widgets/media_send_preview_screen.dart';
import 'package:secure_messenger/presentation/widgets/pending_media_bubble.dart';
import 'package:secure_messenger/presentation/widgets/user_avatar.dart';
import 'package:secure_messenger/presentation/widgets/video_player_screen.dart';

class SecretChatScreen extends StatefulWidget {
  final ChatModel chat;
  final UserModel otherUser;

  const SecretChatScreen(
      {super.key, required this.chat, required this.otherUser});

  @override
  State<SecretChatScreen> createState() => _SecretChatScreenState();
}

class _SecretChatScreenState extends State<SecretChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late SecretMessageProvider _messageProvider;
  late String _currentUid;
  String? _editingMessageId;
  int _inputResetKey = 0;

  @override
  void initState() {
    super.initState();
    _messageProvider = SecretMessageProvider(
      context.read<ChatRepository>(),
      context.read<EncryptionService>(),
    );
    _currentUid = context.read<AuthProvider>().currentUser!.uid;
    _messageProvider.initChat(widget.chat.id, _currentUid);
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
    _messageProvider.stopListening(widget.chat.id, _currentUid);
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
      final editingId = _editingMessageId!;
      _messageController.clear();
      _messageProvider.onTyping(widget.chat.id, uid, false);
      FocusScope.of(context).unfocus();
      setState(() {
        _editingMessageId = null;
        _inputResetKey++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editingMessageId == null) {
          _messageController.clear();
        }
      });
      await _messageProvider.editMessage(
        chatId: widget.chat.id,
        messageId: editingId,
        newContent: text,
      );
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
          accentColor: AppTheme.secretChatColor,
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
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
      allowMultiple: false,
    );
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
                    color: AppTheme.secretChatColor),
                title: const Text('Photos from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImages();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: AppTheme.secretChatColor),
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
                    color: AppTheme.secretChatColor),
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
                    color: AppTheme.secretChatColor),
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
                    color: AppTheme.secretChatColor),
                title: const Text('Edit Message',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _editingMessageId = message.id;
                    _messageController.value = TextEditingValue(
                      text: message.content,
                      selection: TextSelection.collapsed(
                        offset: message.content.length,
                      ),
                    );
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

  List<Widget> _buildItemList(
      List<MessageModel> messages, bool showTyping, String currentUid) {
    final items = <Widget>[];
    DateTime? lastDate;
    for (final msg in messages) {
      final msgDate =
          DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
      if (lastDate == null || msgDate != lastDate) {
        items.add(_SecretDateSeparator(
          key: ValueKey('secret_date_${msgDate.toIso8601String()}'),
          label: DateFormatter.formatDateSeparator(msg.timestamp),
        ));
        lastDate = msgDate;
      }
      items.add(_SecretMessageBubble(
        key: ValueKey('secret_message_${msg.id}'),
        message: msg,
        isMe: msg.senderId == currentUid,
        chatId: widget.chat.id,
        onLongPress: () => _showMessageOptions(msg, currentUid),
      ));
    }
    for (final upload in _messageProvider.pendingMediaUploads) {
      items.add(PendingMediaBubble(
        key: ValueKey('secret_pending_media_${upload.id}'),
        upload: upload,
        accentColor: AppTheme.secretChatColor,
      ));
    }
    if (showTyping) {
      items.add(
        const _SecretTypingIndicator(key: ValueKey('secret_typing_indicator')),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = context.read<AuthProvider>().currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.secretChatColor.withOpacity(0.15),
        leadingWidth: 40,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.lock,
                              size: 14, color: AppTheme.secretChatColor),
                        ],
                      ),
                      Text(
                        user.isOnline
                            ? 'online · encrypted'
                            : user.lastSeen != null
                                ? 'last seen ${timeago.format(user.lastSeen!)} · encrypted'
                                : 'encrypted chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.secretChatColor,
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
                  style:
                      TextStyle(color: AppTheme.secretChatColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: AnimatedBuilder(
                animation: _messageProvider,
                builder: (_, __) {
                  final messages = _messageProvider.messages;
                  final items = _buildItemList(
                    messages,
                    _isOtherUserTyping(),
                    currentUid,
                  );
                  return ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (_, i) => items[i],
                  );
                },
              ),
            ),
          ),
          if (_editingMessageId != null)
            Container(
              color: AppTheme.secretChatColor.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.edit,
                      color: AppTheme.secretChatColor, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Editing message',
                        style: TextStyle(
                            color: AppTheme.secretChatColor, fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: () {
                      _messageController.clear();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _editingMessageId = null;
                        _inputResetKey++;
                      });
                    },
                    child: const Icon(Icons.close,
                        color: AppTheme.subtitleColor, size: 18),
                  ),
                ],
              ),
            ),
          _SecretMessageInput(
            key: ValueKey(
              'secret_message_input_${_inputResetKey}_$_editingMessageId',
            ),
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
  final String chatId;
  final VoidCallback onLongPress;

  const _SecretMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.chatId,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          constraints: BoxConstraints(
            maxWidth:
                (MediaQuery.of(context).size.width * 0.78).clamp(180.0, 420.0),
          ),
          decoration: BoxDecoration(
            color: isMe
                ? AppTheme.secretChatColor.withOpacity(0.85)
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
              else if (message.type == AppConstants.imageMessage &&
                  message.mediaUrl != null)
                _SecretMediaContent(
                  key: ValueKey('secret_media_${message.id}'),
                  url: message.mediaUrl!,
                  type: AppConstants.imageMessage,
                  chatId: chatId,
                )
              else if (message.type == AppConstants.videoMessage &&
                  message.mediaUrl != null)
                _SecretMediaContent(
                  key: ValueKey('secret_media_${message.id}'),
                  url: message.mediaUrl!,
                  type: AppConstants.videoMessage,
                  chatId: chatId,
                )
              else if (message.type == AppConstants.audioMessage &&
                  message.mediaUrl != null)
                _SecretMediaContent(
                  key: ValueKey('secret_media_${message.id}'),
                  url: message.mediaUrl!,
                  type: AppConstants.audioMessage,
                  chatId: chatId,
                )
              else
                Text(
                  message.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.28,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock,
                      size: 10, color: AppTheme.subtitleColor),
                  const SizedBox(width: 3),
                  if (message.isEdited && !message.isDeleted)
                    const Text(
                      'edited · ',
                      style: TextStyle(
                          color: AppTheme.subtitleColor, fontSize: 10),
                    ),
                  Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: const TextStyle(
                      color: AppTheme.subtitleColor,
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

class _SecretMediaContent extends StatefulWidget {
  final String url;
  final String type;
  final String chatId;

  const _SecretMediaContent({
    super.key,
    required this.url,
    required this.type,
    required this.chatId,
  });

  @override
  State<_SecretMediaContent> createState() => _SecretMediaContentState();
}

class _SecretMediaContentState extends State<_SecretMediaContent>
    with AutomaticKeepAliveClientMixin {
  late Future<Uint8List> _mediaFuture;
  late Future<File> _mediaFileFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _createFutures();
  }

  @override
  void didUpdateWidget(covariant _SecretMediaContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.type != widget.type ||
        oldWidget.chatId != widget.chatId) {
      _createFutures();
    }
  }

  void _createFutures() {
    _mediaFuture = _decryptMedia();
    _mediaFileFuture = _decryptMediaFile();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.type == AppConstants.imageMessage) {
      return FutureBuilder<Uint8List>(
        future: _mediaFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _SecretMediaError(
              width: 200,
              height: 200,
              label: 'Unable to decrypt image',
            );
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              width: 200,
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final bytes = snapshot.data!;
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageViewerScreen.bytes(
                  imageBytes: bytes,
                  heroTag: 'secret_${widget.url}',
                ),
              ),
            ),
            child: Hero(
              tag: 'secret_${widget.url}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  bytes,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      );
    }
    if (widget.type == AppConstants.audioMessage) {
      return FutureBuilder<File>(
        future: _mediaFileFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _SecretMediaError(
              width: 220,
              height: 60,
              label: 'Unable to decrypt audio',
            );
          }
          if (!snapshot.hasData) {
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
                builder: (_) => VideoPlayerScreen.file(
                  file: snapshot.data!,
                  isAudio: true,
                ),
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
                    child: Text('Encrypted audio',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return FutureBuilder<File>(
      future: _mediaFileFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SecretMediaError(
            width: 200,
            height: 120,
            label: 'Unable to decrypt video',
          );
        }
        if (!snapshot.hasData) {
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
              builder: (_) => VideoPlayerScreen.file(file: snapshot.data!),
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

  Future<Uint8List> _decryptMedia() async {
    final encryptionService = context.read<EncryptionService>();
    final chatRepository = context.read<ChatRepository>();
    final data = await chatRepository.downloadMediaBytes(widget.url);
    final payload = utf8.decode(data);
    return encryptionService.decryptBytesForChat(payload, widget.chatId);
  }

  Future<File> _decryptMediaFile() async {
    final bytes = await _mediaFuture;
    final directory = await getTemporaryDirectory();
    final extension = widget.type == AppConstants.audioMessage ? 'm4a' : 'mp4';
    final file =
        File('${directory.path}/secret_${widget.url.hashCode}.$extension');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }
}

class _SecretMediaError extends StatelessWidget {
  final double width;
  final double height;
  final String label;

  const _SecretMediaError({
    required this.width,
    required this.height,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, color: AppTheme.errorColor),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SecretDateSeparator extends StatelessWidget {
  final String label;
  const _SecretDateSeparator({super.key, required this.label});

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

class _SecretTypingIndicator extends StatelessWidget {
  const _SecretTypingIndicator({super.key});

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
    super.key,
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
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          top: BorderSide(color: AppTheme.secretChatColor.withOpacity(0.3)),
        ),
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
                  hintText: isEditing ? 'Edit message...' : 'Secret message...',
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
                  color: AppTheme.secretChatColor,
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
