import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/chat_message_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';

class PlayerGameScreen extends ConsumerStatefulWidget {
  final String roomCode;

  const PlayerGameScreen({super.key, required this.roomCode});

  @override
  ConsumerState<PlayerGameScreen> createState() => _PlayerGameScreenState();
}

class _PlayerGameScreenState extends ConsumerState<PlayerGameScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  ChatMessage? _replyingTo;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _setReplyTo(ChatMessage message) {
    setState(() => _replyingTo = message);
  }

  void _clearReply() {
    setState(() => _replyingTo = null);
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomProvider(widget.roomCode));
    final chatAsync = ref.watch(chatProvider(widget.roomCode));
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    // Listen for room status changes
    ref.listen(roomProvider(widget.roomCode), (previous, next) {
      next.whenData((room) {
        if (room != null && room.status == RoomStatus.finished) {
          context.go('/results/${widget.roomCode}');
        }
      });
    });

    // Auto-scroll when new messages arrive
    ref.listen(chatProvider(widget.roomCode), (previous, next) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Game'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
          tooltip: 'Back to Home',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
            child: roomAsync.when(
          data: (room) {
            if (room == null) {
              return const Center(child: Text('Room not found'));
            }

            return _buildGameContent(context, room, chatAsync, currentUser);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameContent(
    BuildContext context,
    RoomModel room,
    AsyncValue<List<ChatMessage>> chatAsync,
    dynamic currentUser,
  ) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // Question section at top
        Container(
          padding: const EdgeInsets.all(16),
          child: _buildQuestionCard(room, l10n),
        ),

        // Divider
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              top: BorderSide(color: Colors.grey.shade300),
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat, size: 20, color: QoomyTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                l10n.chat,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: QoomyTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),

        // Chat messages
        Expanded(
          child: chatAsync.when(
            data: (messages) => _buildChatSection(messages, currentUser?.id, room, l10n),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),

        // Message input
        _buildMessageInput(currentUser, l10n),
      ],
    );
  }

  Widget _buildQuestionCard(RoomModel room, AppLocalizations l10n) {
    return Card(
      color: QoomyTheme.primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.quiz, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.question,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              room.question,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (room.imageUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  room.imageUrl!,
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 100,
                    color: Colors.white24,
                    child: const Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatSection(List<ChatMessage> messages, String? currentUserId, RoomModel room, AppLocalizations l10n) {
    final isAiMode = room.evaluationMode == EvaluationMode.ai;

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              l10n.noMessagesYet,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.sendAnswerOrComment,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMe = message.playerId == currentUserId;
        return _buildMessageBubble(message, isMe, isAiMode: isAiMode, l10n: l10n, allMessages: messages);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe, {bool isAiMode = false, required AppLocalizations l10n, List<ChatMessage>? allMessages}) {
    final isAnswer = message.type == MessageType.answer;
    final isMarked = message.isCorrect != null;

    Color backgroundColor;
    if (isAnswer) {
      if (isMarked) {
        backgroundColor = message.isCorrect!
            ? QoomyTheme.successColor.withOpacity(0.15)
            : QoomyTheme.errorColor.withOpacity(0.15);
      } else {
        backgroundColor = QoomyTheme.primaryColor.withOpacity(0.1);
      }
    } else {
      backgroundColor = isMe ? QoomyTheme.primaryColor.withOpacity(0.15) : Colors.grey.shade100;
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Player name and type badge
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe) ...[
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: QoomyTheme.primaryColor.withOpacity(0.2),
                    child: Text(
                      message.playerName.isNotEmpty ? message.playerName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: QoomyTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  isMe ? l10n.you : message.playerName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isAnswer ? QoomyTheme.primaryColor : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isAnswer ? l10n.answerLabel.toUpperCase() : l10n.comment.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isMarked) ...[
                  const SizedBox(width: 6),
                  Icon(
                    message.isCorrect! ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: message.isCorrect! ? QoomyTheme.successColor : QoomyTheme.errorColor,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),

            // Message bubble with long press for reply
            GestureDetector(
              onLongPress: () => _setReplyTo(message),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reply preview if this is a reply
                    if (message.isReply) ...[
                      _buildReplyPreviewInBubble(message, allMessages, l10n),
                      const SizedBox(height: 8),
                    ],
                    Text(message.text, style: const TextStyle(fontSize: 15)),
                    // AI evaluating indicator (only for answers not yet marked in AI mode)
                    if (isAiMode && isAnswer && !isMarked) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.deepPurple.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.aiEvaluating,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.deepPurple.withOpacity(0.7),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Result indicator (after marked)
                    if (isAnswer && isMarked) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            message.isCorrect! ? Icons.celebration : Icons.sentiment_dissatisfied,
                            size: 16,
                            color: message.isCorrect! ? QoomyTheme.successColor : QoomyTheme.errorColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            message.isCorrect! ? l10n.correct : l10n.wrong,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: message.isCorrect! ? QoomyTheme.successColor : QoomyTheme.errorColor,
                            ),
                          ),
                        ],
                      ),
                      // AI reasoning (only for correct answers)
                      if (isAiMode && message.isCorrect! && message.aiReasoning != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.smart_toy, size: 12, color: Colors.deepPurple),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  message.aiReasoning!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.deepPurple.shade700,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildReplyPreviewInBubble(ChatMessage message, List<ChatMessage>? allMessages, AppLocalizations l10n) {
    String replyText = message.replyToText ?? '';
    String replyPlayerName = message.replyToPlayerName ?? '';

    if (allMessages != null && message.replyToId != null) {
      final originalMessage = allMessages.where((m) => m.id == message.replyToId).firstOrNull;
      if (originalMessage != null) {
        replyText = originalMessage.text;
        replyPlayerName = originalMessage.playerName;
      }
    }

    if (replyText.length > 50) {
      replyText = '${replyText.substring(0, 50)}...';
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(
            color: QoomyTheme.primaryColor,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyPlayerName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: QoomyTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyText.isEmpty ? l10n.hiddenAnswer : replyText,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontStyle: replyText.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar(AppLocalizations l10n) {
    if (_replyingTo == null) return const SizedBox.shrink();

    String replyText = _replyingTo!.text;
    if (replyText.length > 60) {
      replyText = '${replyText.substring(0, 60)}...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: QoomyTheme.primaryColor.withOpacity(0.1),
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          left: const BorderSide(color: QoomyTheme.primaryColor, width: 4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18, color: QoomyTheme.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${l10n.replyingTo} ${_replyingTo!.playerName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: QoomyTheme.primaryColor,
                  ),
                ),
                Text(
                  replyText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _clearReply,
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput(dynamic currentUser, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildReplyBar(l10n),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Text input
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: l10n.typeMessage,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    enabled: !_isSending,
                  ),
                ),
                const SizedBox(width: 8),
                // Comment button (arrow icon)
                IconButton(
                  onPressed: _isSending ? null : () => _sendMessageWithType(currentUser, MessageType.comment),
                  icon: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: Colors.grey),
                  tooltip: l10n.comment,
                ),
                // Answer button
                ElevatedButton(
                  onPressed: _isSending ? null : () => _sendMessageWithType(currentUser, MessageType.answer),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: QoomyTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    l10n.answerLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessageWithType(dynamic currentUser, MessageType type) async {
    if (_messageController.text.trim().isEmpty || currentUser == null) return;

    setState(() => _isSending = true);

    // Prepare reply data if replying
    final replyToId = _replyingTo?.id;
    final replyToText = _replyingTo?.text;
    final replyToPlayerName = _replyingTo?.playerName;

    await ref.read(roomNotifierProvider.notifier).sendMessage(
          roomCode: widget.roomCode,
          playerId: currentUser.id,
          playerName: currentUser.displayName,
          text: _messageController.text.trim(),
          type: type,
          replyToId: replyToId,
          replyToText: replyToText,
          replyToPlayerName: replyToPlayerName,
        );

    if (mounted) {
      setState(() {
        _isSending = false;
        _replyingTo = null;
      });
      _messageController.clear();
    }
  }
}
