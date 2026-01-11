import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/chat_message_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/widgets/app_header.dart';
import 'package:qoomy/widgets/zoomable_image_viewer.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String roomCode;

  const GameScreen({super.key, required this.roomCode});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  bool _questionCollapsed = false; // Collapsed when user scrolls down
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  ChatMessage? _replyingTo; // Message being replied to
  bool _initialScrollDone = false; // Track if we've scrolled on initial load

  // Check if running on desktop (Enter sends message) vs mobile (Enter creates newline)
  bool get _isDesktopPlatform {
    if (kIsWeb) return true; // Web always uses Enter to send
    return defaultTargetPlatform == TargetPlatform.windows ||
           defaultTargetPlatform == TargetPlatform.macOS ||
           defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Mark room as read and scroll to bottom when entering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAsRead();
      // Delay scroll to allow ListView to render with data
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _scrollToBottom();
      });
    });
  }

  void _markAsRead() {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser != null) {
      ref.read(roomServiceProvider).updateLastRead(widget.roomCode, currentUser.id);
    }
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

  void _setReplyTo(ChatMessage message) {
    setState(() => _replyingTo = message);
  }

  void _clearReply() {
    setState(() => _replyingTo = null);
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

    // Auto-scroll when new messages arrive and mark as read
    ref.listen(chatProvider(widget.roomCode), (previous, next) {
      // Scroll on initial load or when new messages arrive
      if (!_initialScrollDone && next.hasValue) {
        _initialScrollDone = true;
        _scrollToBottom();
      } else if (previous != null && previous.hasValue && next.hasValue) {
        // New message arrived
        _scrollToBottom();
      }
      _markAsRead();
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
    // Check if current player has a confirmed correct answer
    final hasCorrectAnswer = chatAsync.whenOrNull(
      data: (messages) => messages.any((msg) =>
          msg.playerId == currentUser?.id &&
          msg.type == MessageType.answer &&
          msg.isCorrect == true),
    ) ?? false;

    // Check if current player has revealed the answer (without answering correctly)
    final hasRevealedAnswer = currentUser != null
        ? ref.watch(hasRevealedAnswerProvider((roomCode: widget.roomCode, userId: currentUser.id))).valueOrNull ?? false
        : false;

    // Combined: user can see answer if they got it right OR revealed it
    final canSeeAnswer = hasCorrectAnswer || hasRevealedAnswer;

    return Column(
      children: [
        // Header with back button, access code, and profile menu
        _buildHeader(context, room, l10n, isHost),

        // Question card (and answer for host or winner) - takes only needed space
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildQuestionCard(room, isHost, l10n),
              if (isHost)
                _buildAnswerSection(room, l10n, isHost: true, hasRevealed: false)
              else if (canSeeAnswer)
                _buildAnswerSection(room, l10n, isHost: false, hasRevealed: hasRevealedAnswer && !hasCorrectAnswer),
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
              canSeeAnswer: canSeeAnswer,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),

        // Message input (different for host and player)
        if (isHost)
          _buildHostMessageInput(room, l10n)
        else
          _buildPlayerMessageInput(currentUser, l10n, cannotAnswer: canSeeAnswer),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, RoomModel room, AppLocalizations l10n, bool isHost) {
    return AppHeader(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
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
      extraMenuItems: isHost
          ? [
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
            ]
          : null,
      onMenuItemSelected: (value) {
        if (value == 'end_game' && isHost) {
          _endGame();
        }
      },
    );
  }

  Widget _buildQuestionCard(RoomModel room, bool isHost, AppLocalizations l10n) {
    // Check if question is long or has an image (both make the card collapsible)
    final hasImage = room.imageUrl != null && room.imageUrl!.isNotEmpty;
    final isLongQuestion = room.question.length > 80;
    final isCollapsible = isLongQuestion || hasImage;
    // Show full question by default, collapse only when scrolled down and content is collapsible
    final showCollapsed = _questionCollapsed && isCollapsible;

    // Calculate max height based on screen size (40% of screen height when expanded)
    final screenHeight = MediaQuery.of(context).size.height;
    final maxExpandedHeight = screenHeight * 0.4;

    return Card(
      color: QoomyTheme.primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.quiz, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.question,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                // Team badge
                if (room.teamName != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          room.teamName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (isCollapsible)
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
            // Scrollable content area for question text and image
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: showCollapsed ? 50 : maxExpandedHeight,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question text
                      Text(
                        room.question,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Image - tappable to open fullscreen viewer
                      if (hasImage && !showCollapsed) ...[
                        const SizedBox(height: 12),
                        ZoomableImageViewer(
                          imageUrl: room.imageUrl!,
                          fit: BoxFit.contain,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerSection(RoomModel room, AppLocalizations l10n, {required bool isHost, bool hasRevealed = false}) {
    // Determine the header text and icon based on who is viewing
    final String headerText;
    final IconData headerIcon;
    final Color headerColor;

    if (isHost) {
      headerText = l10n.correctAnswer;
      headerIcon = Icons.check_circle;
      headerColor = QoomyTheme.successColor;
    } else if (hasRevealed) {
      headerText = l10n.youRevealedAnswer;
      headerIcon = Icons.visibility;
      headerColor = Colors.orange;
    } else {
      headerText = l10n.youGotItRight;
      headerIcon = Icons.emoji_events;
      headerColor = Colors.amber;
    }

    // Hide when question is collapsed
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: _questionCollapsed
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: headerColor.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            headerIcon,
                            color: headerColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            headerText,
                            style: TextStyle(
                              color: isHost ? QoomyTheme.successColor : (hasRevealed ? Colors.orange.shade700 : Colors.amber.shade700),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (isHost) ...[
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
    AppLocalizations l10n, {
    bool canSeeAnswer = false,
  }) {
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
        return _buildMessageBubble(
          message,
          isMe: isMe,
          isAiMode: isAiMode,
          isHost: isHost,
          currentUserId: currentUserId,
          l10n: l10n,
          canSeeAnswer: canSeeAnswer,
          allMessages: messages,
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, {bool isMe = false, bool isAiMode = false, bool isHost = false, String? currentUserId, required AppLocalizations l10n, bool canSeeAnswer = false, List<ChatMessage>? allMessages}) {
    final isAnswer = message.type == MessageType.answer;
    final isMarked = message.isCorrect != null;

    // Determine if the answer should be hidden (applies to both AI and manual mode)
    // Hidden if: answer type + (not evaluated yet OR correct)
    // Visible to: host, the player who sent the answer, OR users who revealed the answer
    // Wrong answers are revealed to everyone after marking
    final bool shouldHideAnswer = isAnswer &&
        !isHost &&
        !canSeeAnswer &&
        message.playerId != currentUserId &&
        (message.isCorrect == null || message.isCorrect == true);

    Color backgroundColor;
    if (shouldHideAnswer) {
      // Hidden answer style - dark/mysterious
      backgroundColor = Colors.grey.shade800;
    } else if (isAnswer) {
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
                        style: const TextStyle(
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
                  const Spacer(),
                  Text(
                    _formatMessageTime(message.sentAt, l10n),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Message content with reply preview
              GestureDetector(
                onLongPress: shouldHideAnswer ? null : () => _setReplyTo(message),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show reply preview if this message is a reply
                      if (message.isReply) ...[
                        _buildReplyPreviewInBubble(message, allMessages, l10n, shouldHideAnswer),
                        const SizedBox(height: 8),
                      ],
                      if (shouldHideAnswer) ...[
                        // Hidden answer display - different text for pending vs correct
                        // Tappable only for correct answers (to reveal)
                        if (message.isCorrect == true)
                          GestureDetector(
                            onTap: () => _showRevealConfirmation(l10n),
                            child: _buildHiddenAnswerContent(true, l10n),
                          )
                        else
                          _buildHiddenAnswerContent(false, l10n),
                      ] else ...[
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
                    ],
                  ),
                ),
              ),

              // AI reasoning (shown after AI marks the answer - only for correct answers, not for hidden answers)
              if (isAiMode && isAnswer && isMarked && message.aiReasoning != null && message.isCorrect == true && !shouldHideAnswer) ...[
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
                        side: const BorderSide(color: QoomyTheme.errorColor),
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
              // Only show for own answers or host - not for hidden answers
              if (isAiMode && isAnswer && !isMarked && !shouldHideAnswer) ...[
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

  Widget _buildReplyPreviewInBubble(ChatMessage message, List<ChatMessage>? allMessages, AppLocalizations l10n, bool isHidden) {
    // Use stored reply text or find the original message
    String replyText = message.replyToText ?? '';
    String replyPlayerName = message.replyToPlayerName ?? '';

    // If we have allMessages, try to find the original for more context
    if (allMessages != null && message.replyToId != null) {
      final originalMessage = allMessages.where((m) => m.id == message.replyToId).firstOrNull;
      if (originalMessage != null) {
        replyText = originalMessage.text;
        replyPlayerName = originalMessage.playerName;
      }
    }

    // Truncate long reply text
    if (replyText.length > 50) {
      replyText = '${replyText.substring(0, 50)}...';
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isHidden ? Colors.grey.shade700 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isHidden ? Colors.grey.shade500 : QoomyTheme.primaryColor,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyPlayerName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isHidden ? Colors.grey.shade400 : QoomyTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyText.isEmpty ? l10n.hiddenAnswer : replyText,
            style: TextStyle(
              fontSize: 12,
              color: isHidden ? Colors.grey.shade400 : Colors.grey.shade700,
              fontStyle: replyText.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHiddenAnswerContent(bool isCorrectAnswer, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isCorrectAnswer ? Icons.emoji_events : Icons.visibility_off,
              size: 16,
              color: isCorrectAnswer ? Colors.amber.shade400 : Colors.grey.shade400,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.hiddenAnswer,
                style: TextStyle(
                  fontSize: 15,
                  color: isCorrectAnswer ? Colors.amber.shade400 : Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isCorrectAnswer ? l10n.tapToRevealCorrectAnswer : l10n.answerHiddenUntilEvaluated,
          style: TextStyle(
            fontSize: 11,
            color: isCorrectAnswer ? Colors.amber.shade300 : Colors.grey.shade500,
          ),
        ),
      ],
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

  Widget _buildHostMessageInput(RoomModel room, AppLocalizations l10n) {
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
                // Text input with keyboard handling (Enter to send on desktop, Shift+Enter for newline)
                Expanded(
                  child: _isDesktopPlatform
                      ? KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              if (!_isSending && _messageController.text.trim().isNotEmpty) {
                                _sendHostMessage(room, l10n);
                              }
                            }
                          },
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
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            enabled: !_isSending,
                            maxLines: 5,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                          ),
                        )
                      : TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: l10n.typeComment,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          enabled: !_isSending,
                          maxLines: 5,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
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
                      : const Icon(Icons.send, color: QoomyTheme.primaryColor, size: 28, weight: 700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerMessageInput(dynamic currentUser, AppLocalizations l10n, {bool cannotAnswer = false}) {
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
                // Text input with keyboard handling (Enter to send on desktop, Shift+Enter for newline)
                Expanded(
                  child: _isDesktopPlatform
                      ? KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              if (!_isSending && _messageController.text.trim().isNotEmpty) {
                                _sendPlayerMessageWithType(currentUser, MessageType.comment);
                              }
                            }
                          },
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
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            enabled: !_isSending,
                            maxLines: 5,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                          ),
                        )
                      : TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: l10n.typeMessage,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          enabled: !_isSending,
                          maxLines: 5,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                        ),
                ),
                const SizedBox(width: 8),
                // Comment button (send icon)
                IconButton(
                  onPressed: _isSending ? null : () => _sendPlayerMessageWithType(currentUser, MessageType.comment),
                  icon: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: QoomyTheme.primaryColor, size: 28, weight: 700),
                  tooltip: l10n.comment,
                ),
              ],
            ),
          ),
          // Answer button - full width red button below input
          if (!cannotAnswer)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSending ? null : () => _sendPlayerMessageWithType(currentUser, MessageType.answer),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: QoomyTheme.errorColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    l10n.giveAnswer,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendHostMessage(RoomModel room, AppLocalizations l10n) async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() => _isSending = true);

    // Prepare reply data if replying
    final replyToId = _replyingTo?.id;
    final replyToText = _replyingTo?.text;
    final replyToPlayerName = _replyingTo?.playerName;

    await ref.read(roomNotifierProvider.notifier).sendMessage(
          roomCode: widget.roomCode,
          playerId: room.hostId,
          playerName: '${room.hostName} (${l10n.host})',
          text: _messageController.text.trim(),
          type: MessageType.comment,
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

  Future<void> _sendPlayerMessageWithType(dynamic currentUser, MessageType type) async {
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

  Future<void> _markAnswer(String messageId, bool isCorrect) async {
    await ref.read(roomNotifierProvider.notifier).markMessageAnswer(
          roomCode: widget.roomCode,
          messageId: messageId,
          isCorrect: isCorrect,
        );
  }

  Future<void> _showRevealConfirmation(AppLocalizations l10n) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.revealAnswerTitle),
        content: Text(l10n.revealAnswerWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(l10n.reveal),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(roomNotifierProvider.notifier).revealAnswer(
        roomCode: widget.roomCode,
        userId: currentUser.id,
      );
    }
  }

  String _formatMessageTime(DateTime time, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    if (messageDate == today) {
      return timeStr;
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return '${l10n.yesterday} $timeStr';
    } else {
      final day = time.day.toString().padLeft(2, '0');
      final month = time.month.toString().padLeft(2, '0');
      return '$day.$month $timeStr';
    }
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
