import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/providers/locale_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/chat_message_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String roomCode;

  const GameScreen({super.key, required this.roomCode});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  bool _showAnswer = false;
  bool _questionCollapsed = false; // Collapsed when user scrolls down
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  MessageType _selectedType = MessageType.answer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // Collapse question when user scrolls down more than 50 pixels
    final shouldCollapse = _scrollController.offset > 50;
    if (shouldCollapse != _questionCollapsed) {
      setState(() => _questionCollapsed = shouldCollapse);
    }
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
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    // Listen for room status changes (redirect to results when game ends)
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

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
            child: roomAsync.when(
              data: (room) {
                if (room == null) {
                  return Center(child: Text(l10n.get('roomNotFound')));
                }

                final isHost = currentUser?.id == room.hostId;
                return _buildGameContent(context, room, playersAsync, chatAsync, l10n, isHost, currentUser);
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
    bool isHost,
    dynamic currentUser,
  ) {
    return Column(
      children: [
        // Header with back button, access code, and end game (host) or language/profile (player)
        _buildHeader(context, room, l10n, isHost, currentUser),

        // Question card (and answer for host) - takes only needed space
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildQuestionCard(room, isHost, l10n),
              if (isHost) ...[
                const SizedBox(height: 12),
                _buildAnswerSection(room, l10n),
              ],
            ],
          ),
        ),

        // Chat section - fills remaining space
        Expanded(
          child: chatAsync.when(
            data: (messages) => _buildChatSection(
              messages,
              room.evaluationMode == EvaluationMode.ai,
              room.hostId,
              currentUser?.id,
              isHost,
              l10n,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),

        // Message input (different for host and player)
        if (isHost)
          _buildHostMessageInput(room, l10n)
        else
          _buildPlayerMessageInput(currentUser, l10n),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, RoomModel room, AppLocalizations l10n, bool isHost, dynamic currentUser) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
            tooltip: l10n.backToHome,
          ),

          // Room code (centered)
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

          // Right side: Language + Profile (for both host and player)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Language toggle
              IconButton(
                icon: Text(
                  ref.watch(localeProvider).languageCode.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onPressed: () {
                  ref.read(localeProvider.notifier).toggleLocale();
                },
                tooltip: l10n.language,
              ),
              // Profile button
              if (currentUser != null)
                PopupMenuButton<String>(
                  icon: CircleAvatar(
                    radius: 14,
                    backgroundColor: QoomyTheme.primaryColor.withOpacity(0.1),
                    backgroundImage: currentUser.avatarUrl != null
                        ? NetworkImage(currentUser.avatarUrl!)
                        : null,
                    child: currentUser.avatarUrl == null
                        ? Text(
                            currentUser.displayName.isNotEmpty
                                ? currentUser.displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: QoomyTheme.primaryColor,
                            ),
                          )
                        : null,
                  ),
                  onSelected: (value) async {
                    if (value == 'logout') {
                      await ref.read(authNotifierProvider.notifier).signOut();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    } else if (value == 'end_game' && isHost) {
                      _endGame();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUser.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            '${l10n.games}: ${currentUser.gamesPlayed} | ${l10n.wins}: ${currentUser.gamesWon}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    if (isHost)
                      PopupMenuItem(
                        value: 'end_game',
                        child: Row(
                          children: [
                            const Icon(Icons.stop, size: 20, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(l10n.endGame, style: const TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          const Icon(Icons.logout, size: 20),
                          const SizedBox(width: 8),
                          Text(l10n.logout),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(RoomModel room, bool isHost, AppLocalizations l10n) {
    // Check if question is long (more than ~80 characters typically means 2+ lines)
    final isLongQuestion = room.question.length > 80;
    // Show full question by default, collapse only when scrolled down and question is long
    final showCollapsed = _questionCollapsed && isLongQuestion;

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
                const Spacer(),
                if (isLongQuestion)
                  IconButton(
                    onPressed: () => setState(() => _questionCollapsed = !_questionCollapsed),
                    icon: Icon(
                      showCollapsed ? Icons.expand_more : Icons.expand_less,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white24,
                      padding: const EdgeInsets.all(4),
                      minimumSize: const Size(32, 32),
                    ),
                    tooltip: showCollapsed ? l10n.show : l10n.hide,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedCrossFade(
              firstChild: Text(
                room.question,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              secondChild: Text(
                room.question,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              crossFadeState: showCollapsed
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 200),
            ),
            if (room.imageUrl != null && room.imageUrl!.isNotEmpty && !showCollapsed) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  room.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 100,
                      color: Colors.white24,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white70),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerSection(RoomModel room, AppLocalizations l10n) {
    return Card(
      color: QoomyTheme.successColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: QoomyTheme.successColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.correctAnswer,
                  style: TextStyle(
                    color: QoomyTheme.successColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Icon(Icons.visibility_off, color: Colors.grey.shade400, size: 16),
                const SizedBox(width: 4),
                Text(
                  l10n.onlyHostCanSee,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
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
        ),
      ),
    );
  }

  Widget _buildChatSection(
    List<ChatMessage> messages,
    bool isAiMode,
    String hostId,
    String? currentUserId,
    bool isHost,
    AppLocalizations l10n,
  ) {
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
              isHost ? 'Players can send comments or answers' : 'Send an answer or comment below',
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
        final isMe = isHost ? message.playerId == hostId : message.playerId == currentUserId;
        return _buildMessageBubble(message, isMe: isMe, isAiMode: isAiMode, isHost: isHost, l10n: l10n);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, {bool isMe = false, bool isAiMode = false, bool isHost = false, required AppLocalizations l10n}) {
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMe) ...[
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: QoomyTheme.primaryColor.withOpacity(0.2),
                      child: Text(
                        message.playerName.isNotEmpty ? message.playerName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: QoomyTheme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    isMe ? l10n.you : message.playerName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAnswer ? QoomyTheme.primaryColor : Colors.grey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isAnswer ? l10n.answerLabel.toUpperCase() : l10n.comment.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (isMarked) ...[
                    const SizedBox(width: 8),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.text, style: const TextStyle(fontSize: 15)),
                    // Player-specific: Result indicator after marked
                    if (!isHost && isAnswer && isMarked) ...[
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
                    ],
                  ],
                ),
              ),

              // AI reasoning (shown after AI marks the answer)
              if (isAiMode && isAnswer && isMarked && message.aiReasoning != null) ...[
                const SizedBox(height: 6),
                _buildAiReasoningBadge(message),
              ],

              // Host-only: Mark buttons for answers (only in manual mode)
              if (isHost && !isAiMode && isAnswer && !isMarked) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _markAnswer(message.id, false),
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(l10n.wrong),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: QoomyTheme.errorColor,
                        side: BorderSide(color: QoomyTheme.errorColor),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _markAnswer(message.id, true),
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(l10n.correct),
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

  Widget _buildAiReasoningBadge(ChatMessage message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smart_toy,
            size: 14,
            color: Colors.deepPurple,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message.aiReasoning!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.deepPurple.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostMessageInput(RoomModel room, AppLocalizations l10n) {
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
            child: Text(
              l10n.host.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: l10n.typeComment,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              enabled: !_isSending,
              onSubmitted: (_) => _sendHostMessage(room, l10n),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : () => _sendHostMessage(room, l10n),
            icon: _isSending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.send, color: QoomyTheme.primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerMessageInput(dynamic currentUser, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // Type selector (Answer / Comment)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = MessageType.answer),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectedType == MessageType.answer
                          ? QoomyTheme.primaryColor
                          : Colors.grey.shade200,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.answerLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedType == MessageType.answer ? Colors.white : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = MessageType.comment),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectedType == MessageType.comment
                          ? Colors.grey.shade600
                          : Colors.grey.shade200,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.comment,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedType == MessageType.comment ? Colors.white : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Text input and send button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: _selectedType == MessageType.answer
                        ? l10n.typeAnswer
                        : l10n.typeComment,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  enabled: !_isSending,
                  onSubmitted: (_) => _sendPlayerMessage(currentUser),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSending ? null : () => _sendPlayerMessage(currentUser),
                icon: _isSending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.send, color: QoomyTheme.primaryColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendHostMessage(RoomModel room, AppLocalizations l10n) async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() => _isSending = true);

    await ref.read(roomNotifierProvider.notifier).sendMessage(
          roomCode: widget.roomCode,
          playerId: room.hostId,
          playerName: '${room.hostName} (${l10n.host})',
          text: _messageController.text.trim(),
          type: MessageType.comment,
        );

    if (mounted) {
      setState(() => _isSending = false);
      _messageController.clear();
    }
  }

  Future<void> _sendPlayerMessage(dynamic currentUser) async {
    if (_messageController.text.trim().isEmpty || currentUser == null) return;

    setState(() => _isSending = true);

    await ref.read(roomNotifierProvider.notifier).sendMessage(
          roomCode: widget.roomCode,
          playerId: currentUser.id,
          playerName: currentUser.displayName,
          text: _messageController.text.trim(),
          type: _selectedType,
        );

    if (mounted) {
      setState(() => _isSending = false);
      _messageController.clear();
    }
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
