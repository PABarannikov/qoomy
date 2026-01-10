import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/providers/team_provider.dart';
import 'package:qoomy/models/room_model.dart';
import 'package:qoomy/models/team_model.dart';
import 'package:qoomy/config/theme.dart';
import 'package:qoomy/l10n/app_localizations.dart';
import 'package:qoomy/widgets/app_header.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _answerController = TextEditingController();
  final _commentController = TextEditingController();

  EvaluationMode _selectedMode = EvaluationMode.ai;
  bool _isCreating = false;
  Uint8List? _selectedImage;
  TeamModel? _selectedTeam;

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImage = bytes;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _createRoom() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    setState(() => _isCreating = true);

    final roomCode = await ref.read(roomNotifierProvider.notifier).createRoom(
          hostId: currentUser.id,
          hostName: currentUser.displayName,
          evaluationMode: _selectedMode,
          question: _questionController.text.trim(),
          answer: _answerController.text.trim(),
          comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
          imageBytes: _selectedImage,
          teamId: _selectedTeam?.id,
        );

    if (mounted) {
      setState(() => _isCreating = false);
      if (roomCode != null) {
        context.go('/');
      } else {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToCreateRoom),
            backgroundColor: QoomyTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: l10n.createRoom,
              showBackButton: true,
              showTeamsButton: false,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Question Field
                          Text(
                            l10n.question,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _questionController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: l10n.questionHint,
                              prefixIcon: const Icon(Icons.help_outline),
                              alignLabelWithHint: true,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.enterQuestion;
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // Image Field (Optional)
                          Text(
                            l10n.imageOptional,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          if (_selectedImage != null) ...[
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    _selectedImage!,
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    onPressed: _removeImage,
                                    icon: const Icon(Icons.close),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.image_outlined),
                              label: Text(l10n.addImage),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Answer Field
                          Text(
                            l10n.correctAnswer,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.onlyYouSeeThis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _answerController,
                            decoration: InputDecoration(
                              hintText: l10n.answerHint,
                              prefixIcon: const Icon(Icons.check_circle_outline),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.enterAnswer;
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // Comment Field (Optional)
                          Text(
                            l10n.commentOptional,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.commentDescription,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _commentController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: l10n.addExplanation,
                              prefixIcon: const Icon(Icons.comment_outlined),
                              alignLabelWithHint: true,
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Evaluation Mode Selection
                          Text(
                            l10n.evaluationMode,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),

                          // Manual Mode Card
                          _buildModeCard(
                            mode: EvaluationMode.manual,
                            title: l10n.manual,
                            description: l10n.manualDesc,
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 12),

                          // AI Mode Card
                          _buildModeCard(
                            mode: EvaluationMode.ai,
                            title: l10n.aiAssisted,
                            description: l10n.aiAssistedDesc,
                            icon: Icons.smart_toy_outlined,
                          ),

                          const SizedBox(height: 32),

                          // Team Selection
                          _buildTeamSelector(),

                          const SizedBox(height: 32),

                          // Create Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isCreating ? null : _createRoom,
                              child: _isCreating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(l10n.createRoom),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required EvaluationMode mode,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == mode;

    return GestureDetector(
      onTap: () => setState(() => _selectedMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? QoomyTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? QoomyTheme.primaryColor.withOpacity(0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? QoomyTheme.primaryColor
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? QoomyTheme.primaryColor
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: QoomyTheme.primaryColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamSelector() {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final l10n = AppLocalizations.of(context);

    if (currentUser == null) return const SizedBox.shrink();

    final teamsAsync = ref.watch(userTeamsProvider(currentUser.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.selectTeam,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.selectTeamDescription,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
        ),
        const SizedBox(height: 12),
        teamsAsync.when(
          data: (teams) => Column(
            children: [
              // No Team option
              _buildTeamCard(null),
              ...teams.map((team) => _buildTeamCard(team)),
            ],
          ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }

  Widget _buildTeamCard(TeamModel? team) {
    final isSelected = _selectedTeam?.id == team?.id;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedTeam = team),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? QoomyTheme.primaryColor : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? QoomyTheme.primaryColor.withOpacity(0.1)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: team == null
                    ? Colors.grey.shade200
                    : QoomyTheme.primaryColor.withOpacity(0.1),
                child: team == null
                    ? Icon(Icons.group_off, color: Colors.grey.shade600)
                    : Text(
                        team.name.isNotEmpty ? team.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: QoomyTheme.primaryColor,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team?.name ?? l10n.noTeam,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? QoomyTheme.primaryColor
                            : Colors.black87,
                      ),
                    ),
                    if (team != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${team.memberCount} ${l10n.members.toLowerCase()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: QoomyTheme.primaryColor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
