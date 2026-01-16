import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/chat_message_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/widgets/zoomable_image_viewer.dart';

class HostGameScreen extends ConsumerStatefulWidget {
  final String roomCode;

  const HostGameScreen({super.key, required this.roomCode});

  @override
  ConsumerState<HostGameScreen> createState() => _HostGameScreenState();
}

class _HostGameScreenState extends ConsumerState<HostGameScreen> {
  bool _showAnswer = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomProvider(widget.roomCode));
    final playersAsync = ref.watch(playersProvider(widget.roomCode));
    final chatAsync = ref.watch(chatProvider(widget.roomCode));

    // Auto-scroll when new messages arrive
    ref.listen(chatProvider(widget.roomCode), (previous, next) {
      _scrollToBottom();
    });

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
            child: roomAsync.when(
              data: (room) {
                if (room == null) {
                  return const Center(child: Text('Room not found'));
                }

                return _buildGameContent(context, room, playersAsync, chatAsync, l10n);
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
    AsyncValue<List<Player>> playersAsync,
    AsyncValue<List<ChatMessage>> chatAsync,
    AppLocalizations l10n,
  ) {
    return Column(
      children: [
        // Header with back button, access code, and end game
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/'),
                tooltip: l10n.backToHome,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${l10n.accessCode}: ',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      widget.roomCode,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.roomCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.get('codeCopied')),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy, size: 16),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _endGame(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stop, color: Colors.red, size: 18),
                    const SizedBox(width: 4),
                    Text(l10n.endGame, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Top section with question, answer
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQuestionCard(room),
                const SizedBox(height: 16),
                _buildAnswerSection(room),
              ],
            ),
          ),
        ),

        // Divider with player count
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
              const Text(
                'Chat',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: QoomyTheme.primaryColor,
                ),
              ),
              const Spacer(),
              playersAsync.when(
                data: (players) => Text(
                  '${players.length} players',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),

        // Chat section
        Expanded(
          flex: 3,
          child: chatAsync.when(
            data: (messages) => _buildChatSection(messages, room.evaluationMode == EvaluationMode.ai, room.hostId),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),

        // Host message input
        _buildHostMessageInput(room),
      ],
    );
  }

  Widget _buildHostMessageInput(RoomModel room) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'HOST',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              enabled: !_isSending,
              onSubmitted: (_) => _sendHostMessage(room),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : () => _sendHostMessage(room),
            icon: _isSending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, color: QoomyTheme.primaryColor),
          ),
        ],
      ),
    );
  }

  Future<void> _sendHostMessage(RoomModel room) async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() => _isSending = true);

    await ref.read(roomNotifierProvider.notifier).sendMessage(
          roomCode: widget.roomCode,
          playerId: room.hostId,
          playerName: '${room.hostName} (Host)',
          text: _messageController.text.trim(),
          type: MessageType.comment,
        );

    if (mounted) {
      setState(() => _isSending = false);
      _messageController.clear();
    }
  }


  Widget _buildQuestionCard(RoomModel room) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.quiz, color: QoomyTheme.primaryColor, size: 20),
                SizedBox(width: 8),
                Text(
                  'Question',
                  style: TextStyle(
                    color: QoomyTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              room.question,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            if (room.imageUrl != null) ...[
              const SizedBox(height: 12),
              ZoomableImageViewer(
                imageUrl: room.imageUrl!,
                height: 120,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerSection(RoomModel room) {
    return Card(
      color: _showAnswer ? QoomyTheme.successColor.withOpacity(0.1) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: QoomyTheme.successColor, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Correct Answer',
                      style: TextStyle(
                        color: QoomyTheme.successColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() => _showAnswer = !_showAnswer),
                  child: Text(_showAnswer ? 'Hide' : 'Show'),
                ),
              ],
            ),
            if (_showAnswer) ...[
              const SizedBox(height: 8),
              Text(room.answer, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              if (room.comment != null && room.comment!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  room.comment!,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatSection(List<ChatMessage> messages, bool isAiMode, String hostId) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Players can send comments or answers',
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
        final isMe = message.playerId == hostId;
        return _buildMessageBubble(message, isMe: isMe, isAiMode: isAiMode);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, {bool isMe = false, bool isAiMode = false}) {
    final isAnswer = message.type == MessageType.answer;
    final isMarked = message.isCorrect != null;

    Color backgroundColor;
    if (isAnswer) {
      if (isMarked) {
        backgroundColor = message.isCorrect!
            ? QoomyTheme.successColor.withOpacity(0.1)
            : QoomyTheme.errorColor.withOpacity(0.1);
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
            // Player name and message type
            Row(
              children: [
                if (!isMe) ...[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: QoomyTheme.primaryColor.withOpacity(0.2),
                    child: Text(
                      message.playerName.isNotEmpty ? message.playerName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: QoomyTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    isMe ? 'You' : message.playerName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isAnswer ? QoomyTheme.primaryColor : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isAnswer ? 'ANSWER' : 'COMMENT',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isMarked) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isCorrect! ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: message.isCorrect! ? QoomyTheme.successColor : QoomyTheme.errorColor,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            // Message content
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(message.text, style: const TextStyle(fontSize: 15)),
            ),


            // Mark buttons for answers (only in manual mode)
            if (!isAiMode && isAnswer && !isMarked) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _markAnswer(message.id, false),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Wrong'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: QoomyTheme.errorColor,
                      side: const BorderSide(color: QoomyTheme.errorColor),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _markAnswer(message.id, true),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Correct'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: QoomyTheme.successColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                ],
              ),
            ],

            // Waiting for AI indicator (in AI mode, answer not yet marked)
            if (isAiMode && isAnswer && !isMarked) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.deepPurple.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI is evaluating...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.deepPurple.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _markAnswer(String messageId, bool isCorrect) async {
    await ref.read(roomNotifierProvider.notifier).markMessageAnswer(
          roomCode: widget.roomCode,
          messageId: messageId,
          isCorrect: isCorrect,
        );
  }

  Future<void> _endGame() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Game?'),
        content: const Text('This will end the game for all players.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: QoomyTheme.errorColor),
            child: const Text('End Game'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(roomNotifierProvider.notifier).endGame(widget.roomCode);
      if (mounted) {
        context.go('/results/${widget.roomCode}');
      }
    }
  }
}
