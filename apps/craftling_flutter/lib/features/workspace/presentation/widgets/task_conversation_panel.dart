import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/network/craftling_gateway_url.dart';
import '../../../../core/utils/assistant_parser.dart';
import '../../domain/workspace_models.dart';
import '../theme/workspace_colors.dart';
import 'workspace_shared.dart';

enum TaskConversationViewMode { start, task, settings, usage }

class TaskConversationPanel extends StatefulWidget {
  const TaskConversationPanel({
    super.key,
    required this.viewMode,
    required this.selectedTask,
    required this.backendServiceUrl,
    required this.isBackendOnline,
    required this.inProgressTasks,
    required this.pendingApprovalTasks,
    required this.completedTasks,
    required this.onStartTask,
    required this.onContinueTask,
    required this.onTaskSelected,
    required this.onPinTask,
    required this.onRenameTask,
    required this.onDeleteTask,
    required this.onBack,
    required this.onApprove,
    required this.onBackendServiceUrlChanged,
    required this.onBackendConnectionStateChanged,
  });

  final TaskConversationViewMode viewMode;
  final TaskWorkspaceData? selectedTask;
  final String backendServiceUrl;
  final bool isBackendOnline;
  final List<TaskWorkspaceData> inProgressTasks;
  final List<TaskWorkspaceData> pendingApprovalTasks;
  final List<TaskWorkspaceData> completedTasks;
  final ValueChanged<String> onStartTask;
  final ValueChanged<String> onContinueTask;
  final ValueChanged<String> onTaskSelected;
  final ValueChanged<String> onPinTask;
  final ValueChanged<String> onRenameTask;
  final ValueChanged<String> onDeleteTask;
  final VoidCallback onBack;
  final VoidCallback onApprove;
  final ValueChanged<String> onBackendServiceUrlChanged;
  final ValueChanged<bool> onBackendConnectionStateChanged;

  @override
  State<TaskConversationPanel> createState() => _TaskConversationPanelState();
}

class _TaskConversationPanelState extends State<TaskConversationPanel> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _settingsController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _settingsErrorText;
  String? _settingsInfoText;

  @override
  void didUpdateWidget(covariant TaskConversationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backendServiceUrl != widget.backendServiceUrl ||
        oldWidget.viewMode != widget.viewMode) {
      _settingsController.text = widget.backendServiceUrl;
    }

    if (oldWidget.isBackendOnline != widget.isBackendOnline) {
      _settingsErrorText = null;
      _settingsInfoText = widget.isBackendOnline
          ? 'Connected to Craftling Gateway.'
          : 'Craftling Gateway is offline.';
    }

    if (oldWidget.selectedTask?.task.id != widget.selectedTask?.task.id) {
      _inputController.clear();
      _scrollToBottom(jump: true);
      return;
    }

    final List<ChatMessageData> previousMessages =
        oldWidget.selectedTask?.messages ?? const <ChatMessageData>[];
    final List<ChatMessageData> currentMessages =
        widget.selectedTask?.messages ?? const <ChatMessageData>[];
    final String previousLastText = previousMessages.isEmpty
        ? ''
        : previousMessages.last.text;
    final String currentLastText = currentMessages.isEmpty
        ? ''
        : currentMessages.last.text;
    if (currentMessages.length > previousMessages.length ||
        currentLastText != previousLastText) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _settingsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }

    if (widget.selectedTask == null) {
      widget.onStartTask(text);
    } else {
      widget.onContinueTask(text);
    }
    _inputController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final double offset = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(offset);
        return;
      }
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handleSettingsPrimaryAction() {
    if (widget.isBackendOnline) {
      widget.onBackendConnectionStateChanged(false);
      setState(() {
        _settingsErrorText = null;
        _settingsInfoText = 'Disconnected from Craftling Gateway.';
      });
      return;
    }

    final String candidate = _settingsController.text.trim();
    final bool looksValid = toCraftlingGatewayWebSocketUrl(candidate) != null;

    if (!looksValid) {
      widget.onBackendConnectionStateChanged(false);
      setState(() {
        _settingsInfoText = null;
        _settingsErrorText =
            'Unable to connect. Enter a valid Craftling Gateway URL.';
      });
      return;
    }

    widget.onBackendServiceUrlChanged(candidate);
    widget.onBackendConnectionStateChanged(true);
    setState(() {
      _settingsErrorText = null;
      _settingsInfoText = 'Connecting to Craftling Gateway...';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_settingsController.text != widget.backendServiceUrl) {
      _settingsController.text = widget.backendServiceUrl;
    }

    if (widget.viewMode == TaskConversationViewMode.settings) {
      return PanelShell(
        child: _SettingsCenterState(
          controller: _settingsController,
          isConnected: widget.isBackendOnline,
          errorText: _settingsErrorText,
          infoText: _settingsInfoText,
          onApply: _handleSettingsPrimaryAction,
          onHome: widget.onBack,
        ),
      );
    }

    if (widget.viewMode == TaskConversationViewMode.usage) {
      return PanelShell(child: _UsageCenterState(onHome: widget.onBack));
    }

    final TaskWorkspaceData? selectedTask = widget.selectedTask;
    if (widget.viewMode == TaskConversationViewMode.start ||
        selectedTask == null) {
      return PanelShell(
        child: _NewTaskStartState(
          controller: _inputController,
          inProgressTasks: widget.inProgressTasks,
          pendingApprovalTasks: widget.pendingApprovalTasks,
          completedTasks: widget.completedTasks,
          onStartTask: _submit,
          onTaskSelected: widget.onTaskSelected,
          onPinTask: widget.onPinTask,
          onRenameTask: widget.onRenameTask,
          onDeleteTask: widget.onDeleteTask,
        ),
      );
    }

    return PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _HeaderHomeButton(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedTask.task.title,
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PhaseProgressBar(currentPhase: selectedTask.phase),
          const SizedBox(height: 14),
          SummaryStatusLine(text: selectedTask.summaryLine),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: selectedTask.messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (BuildContext context, int index) {
                final ChatMessageData message = selectedTask.messages[index];
                switch (message.type) {
                  case MessageType.user:
                    return UserChatBubble(message: message);
                  case MessageType.agent:
                    return AgentChatBubble(message: message);
                  case MessageType.approval:
                    return ApprovalBubble(
                      message: message,
                      onApprove: widget.onApprove,
                    );
                }
              },
            ),
          ),
          const SizedBox(height: 18),
          ComposerBar(
            controller: _inputController,
            buttonLabel: 'Send',
            hintText: 'Add a follow-up or continue the task...',
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

class _SettingsCenterState extends StatelessWidget {
  const _SettingsCenterState({
    required this.controller,
    required this.isConnected,
    required this.errorText,
    required this.infoText,
    required this.onApply,
    required this.onHome,
  });

  final TextEditingController controller;
  final bool isConnected;
  final String? errorText;
  final String? infoText;
  final VoidCallback onApply;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _HeaderHomeButton(onPressed: onHome),
            const SizedBox(width: 12),
            const Text(
              'Settings',
              style: TextStyle(
                color: textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Workspace-level configuration for the Craftling Gateway.',
          style: TextStyle(color: textSecondary, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: bubbleSurfaceAlt,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: panelBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Craftling Gateway URL',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: defaultCraftlingGatewayUrl,
                    hintStyle: const TextStyle(color: mutedText, fontSize: 14),
                    filled: true,
                    fillColor: panelBackground,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: panelBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: primaryBlue),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: (isConnected ? successGreen : dangerRed).withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (isConnected ? successGreen : dangerRed)
                          .withValues(alpha: 0.32),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isConnected
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        size: 16,
                        color: isConnected ? successGreen : dangerRed,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnected ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: isConnected ? successGreen : dangerRed,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Use the Gateway base URL. Craftling will connect to '
                  '/__craftling__/ws automatically.',
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                if (errorText != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      color: dangerRed,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (infoText != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    infoText!,
                    style: TextStyle(
                      color: isConnected ? successGreen : textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    FilledButton(
                      onPressed: onApply,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(isConnected ? 'Disconnect' : 'Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UsageCenterState extends StatelessWidget {
  const _UsageCenterState({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _HeaderHomeButton(onPressed: onHome),
            const SizedBox(width: 12),
            const Text(
              'Token Usage',
              style: TextStyle(
                color: textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Usage insights will appear here once workspace-level tracking is connected.',
          style: TextStyle(color: textSecondary, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 28),
        Expanded(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bubbleSurfaceAlt,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: panelBorder),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.stacked_bar_chart_rounded,
                    color: textSecondary,
                    size: 34,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Usage data is not connected yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This placeholder page reserves space for future token, cost, and model activity reporting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderHomeButton extends StatelessWidget {
  const _HeaderHomeButton({
    required this.onPressed,
    this.label = 'Home',
    this.icon = Icons.home_rounded,
  });

  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        backgroundColor: bubbleSurfaceAlt,
        side: const BorderSide(color: panelBorder),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _NewTaskStartState extends StatelessWidget {
  const _NewTaskStartState({
    required this.controller,
    required this.inProgressTasks,
    required this.pendingApprovalTasks,
    required this.completedTasks,
    required this.onStartTask,
    required this.onTaskSelected,
    required this.onPinTask,
    required this.onRenameTask,
    required this.onDeleteTask,
  });

  final TextEditingController controller;
  final List<TaskWorkspaceData> inProgressTasks;
  final List<TaskWorkspaceData> pendingApprovalTasks;
  final List<TaskWorkspaceData> completedTasks;
  final VoidCallback onStartTask;
  final ValueChanged<String> onTaskSelected;
  final ValueChanged<String> onPinTask;
  final ValueChanged<String> onRenameTask;
  final ValueChanged<String> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Start a new task',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Describe the task in one sentence. The agent will plan, execute, and return results.',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: bubbleSurfaceAlt,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: panelBorder),
                ),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Example: Update the enemy patrol logic to use a three-stage path and validate the animations in Level_A.',
                        hintStyle: const TextStyle(
                          color: mutedText,
                          fontSize: 15,
                          height: 1.5,
                        ),
                        filled: true,
                        fillColor: panelBackground,
                        contentPadding: const EdgeInsets.all(18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: panelBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: primaryBlue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.start,
                            children: <Widget>[
                              _SuggestionChip(
                                label: 'Refine AI patrol behavior',
                                onTap: () {
                                  controller.text =
                                      'Refine the enemy patrol behavior in Level_A and validate movement transitions.';
                                },
                              ),
                              _SuggestionChip(
                                label: 'Fix spawn validation issue',
                                onTap: () {
                                  controller.text =
                                      'Investigate the NPC spawn validation issue and verify the fix in scene_02.';
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton(
                          onPressed: onStartTask,
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Start Task'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 370,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _StartTaskColumn(
                  title: 'In Progress',
                  tasks: inProgressTasks,
                  accentColor: primaryBlue,
                  emptyText: 'No tasks in progress.',
                  onTaskSelected: onTaskSelected,
                  onPinTask: onPinTask,
                  onRenameTask: onRenameTask,
                  onDeleteTask: onDeleteTask,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StartTaskColumn(
                  title: 'Pending Approval',
                  tasks: pendingApprovalTasks,
                  accentColor: warningAmber,
                  emptyText: 'No tasks waiting for approval.',
                  onTaskSelected: onTaskSelected,
                  onPinTask: onPinTask,
                  onRenameTask: onRenameTask,
                  onDeleteTask: onDeleteTask,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StartTaskColumn(
                  title: 'Completed',
                  tasks: completedTasks,
                  accentColor: successGreen,
                  emptyText: 'No completed tasks yet.',
                  onTaskSelected: onTaskSelected,
                  onPinTask: onPinTask,
                  onRenameTask: onRenameTask,
                  onDeleteTask: onDeleteTask,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _StartTaskColumn extends StatelessWidget {
  const _StartTaskColumn({
    required this.title,
    required this.tasks,
    required this.accentColor,
    required this.emptyText,
    required this.onTaskSelected,
    required this.onPinTask,
    required this.onRenameTask,
    required this.onDeleteTask,
  });

  final String title;
  final List<TaskWorkspaceData> tasks;
  final Color accentColor;
  final String emptyText;
  final ValueChanged<String> onTaskSelected;
  final ValueChanged<String> onPinTask;
  final ValueChanged<String> onRenameTask;
  final ValueChanged<String> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bubbleSurfaceAlt,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${tasks.length}',
                style: const TextStyle(
                  color: mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final TaskWorkspaceData task = tasks[index];
                      return _StartTaskCard(
                        task: task,
                        accentColor: accentColor,
                        onTap: () => onTaskSelected(task.task.id),
                        onPin: () => onPinTask(task.task.id),
                        onRename: () => onRenameTask(task.task.id),
                        onDelete: () => onDeleteTask(task.task.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StartTaskCard extends StatefulWidget {
  const _StartTaskCard({
    required this.task,
    required this.accentColor,
    required this.onTap,
    required this.onPin,
    required this.onRename,
    required this.onDelete,
  });

  final TaskWorkspaceData task;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_StartTaskCard> createState() => _StartTaskCardState();
}

class _StartTaskCardState extends State<_StartTaskCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color statusAccent = statusColor(widget.task.task.status);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            _pressed ? 1 : (_hovered ? -2 : 0),
            0,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovered ? panelBackgroundAlt : panelBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? widget.accentColor.withValues(alpha: 0.36)
                  : panelBorder,
            ),
            boxShadow: _hovered
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.task.task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<_StartTaskCardAction>(
                      tooltip: 'Manage task',
                      padding: EdgeInsets.zero,
                      splashRadius: 16,
                      offset: const Offset(0, 30),
                      color: const Color(0xFF101825),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: panelBorder),
                      ),
                      onSelected: (_StartTaskCardAction value) {
                        switch (value) {
                          case _StartTaskCardAction.pinToTop:
                            widget.onPin();
                          case _StartTaskCardAction.rename:
                            widget.onRename();
                          case _StartTaskCardAction.delete:
                            widget.onDelete();
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          const <PopupMenuEntry<_StartTaskCardAction>>[
                            PopupMenuItem<_StartTaskCardAction>(
                              value: _StartTaskCardAction.pinToTop,
                              child: _StartTaskCardMenuItem(
                                icon: Icons.vertical_align_top_rounded,
                                label: 'Pin to top',
                              ),
                            ),
                            PopupMenuItem<_StartTaskCardAction>(
                              value: _StartTaskCardAction.rename,
                              child: _StartTaskCardMenuItem(
                                icon: Icons.drive_file_rename_outline_rounded,
                                label: 'Rename',
                              ),
                            ),
                            PopupMenuItem<_StartTaskCardAction>(
                              value: _StartTaskCardAction.delete,
                              child: _StartTaskCardMenuItem(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                              ),
                            ),
                          ],
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: _hovered ? textSecondary : mutedText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.task.summaryLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  StatusBadge(
                    label: statusLabel(widget.task.task.status),
                    color: statusAccent,
                  ),
                  const Spacer(),
                  Text(
                    phaseLabel(widget.task.phase),
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StartTaskCardAction { pinToTop, rename, delete }

class _StartTaskCardMenuItem extends StatelessWidget {
  const _StartTaskCardMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: panelBackgroundAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: panelBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class PhaseProgressBar extends StatelessWidget {
  const PhaseProgressBar({super.key, required this.currentPhase});

  final TaskPhase currentPhase;

  @override
  Widget build(BuildContext context) {
    final List<TaskPhase> phases = TaskPhase.values;
    return Row(
      children: phases.map((TaskPhase phase) {
        final int index = phases.indexOf(phase);
        final int currentIndex = phases.indexOf(currentPhase);
        final bool isComplete = index < currentIndex;
        final bool isCurrent = index == currentIndex;
        final bool hasLeftConnector = index != 0;
        final bool hasRightGap = index != phases.length - 1;
        final Color fill = isCurrent
            ? primaryBlue
            : isComplete
            ? successGreen
            : primaryBlueSoft;
        final Color surface = isCurrent
            ? primaryBlue.withValues(alpha: 0.20)
            : isComplete
            ? successGreen.withValues(alpha: 0.14)
            : bubbleSurfaceAlt;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: hasRightGap ? 8 : 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (hasLeftConnector)
                  Positioned(
                    left: -12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: isComplete || isCurrent
                            ? fill.withValues(alpha: 0.9)
                            : panelBorder,
                      ),
                    ),
                  ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    hasLeftConnector ? 18 : 14,
                    12,
                    14,
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isCurrent
                          ? fill
                          : isComplete
                          ? successGreen.withValues(alpha: 0.5)
                          : panelBorder,
                    ),
                    boxShadow: isCurrent
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x224C7DFF),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: fill.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCurrent
                                ? fill
                                : isComplete
                                ? successGreen.withValues(alpha: 0.6)
                                : panelBorder,
                          ),
                        ),
                        child: Icon(
                          isComplete ? Icons.check_rounded : Icons.circle,
                          size: isComplete ? 13 : 9,
                          color: isComplete ? successGreen : fill,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              phaseLabel(phase),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent || isComplete
                                    ? textPrimary
                                    : textSecondary,
                                fontSize: 12,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: fill,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class SummaryStatusLine extends StatelessWidget {
  const SummaryStatusLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class UserChatBubble extends StatelessWidget {
  const UserChatBubble({super.key, required this.message});

  final ChatMessageData message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: primaryBlue,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                message.text,
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              if (message.timestamp != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  message.timestamp!,
                  style: const TextStyle(
                    color: Color(0xFFD8E2FF),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AgentChatBubble extends StatelessWidget {
  const AgentChatBubble({super.key, required this.message});

  final ChatMessageData message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: bubbleSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: panelBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const AgentIdentityRow(label: 'Main Agent', chipLabel: 'Running'),
              const SizedBox(height: 12),
              MarkdownBody(
                data: message.text,
                selectable: true,
                softLineBreak: true,
                styleSheet: buildAssistantMarkdownStyleSheet(context).copyWith(
                  p: const TextStyle(
                    color: textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                  strong: const TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                  ),
                  code: const TextStyle(
                    color: Color(0xFFD7E4FF),
                    backgroundColor: Color(0xFF18243A),
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (message.timestamp != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  message.timestamp!,
                  style: const TextStyle(color: mutedText, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ApprovalBubble extends StatelessWidget {
  const ApprovalBubble({
    super.key,
    required this.message,
    required this.onApprove,
  });

  final ChatMessageData message;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: approvalSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF3D5685)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const AgentIdentityRow(
                label: 'Main Agent',
                chipLabel: 'Approval Required',
                chipColor: warningAmber,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          message.title ?? '',
                          style: const TextStyle(
                            color: textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message.text,
                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...(message.bullets ?? <String>[]).map(
                          (String bullet) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(top: 7),
                                  decoration: const BoxDecoration(
                                    color: successGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    bullet,
                                    style: const TextStyle(
                                      color: textSecondary,
                                      fontSize: 13.5,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 132,
                    height: 112,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22314B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: panelBorder),
                    ),
                    child: Center(
                      child: Text(
                        message.previewLabel ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (message.isApproved)
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: successGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: successGreen.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: successGreen,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            message.approvalStatusText ?? 'Approved',
                            style: const TextStyle(
                              color: successGreen,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (message.timestamp != null)
                      Text(
                        message.timestamp!,
                        style: const TextStyle(color: mutedText, fontSize: 11),
                      ),
                  ],
                )
              else
                Row(
                  children: <Widget>[
                    FilledButton(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        backgroundColor: successGreen,
                        foregroundColor: pageBackground,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        side: const BorderSide(color: panelBorder),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        side: const BorderSide(color: panelBorder),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Ask a follow-up'),
                    ),
                    const Spacer(),
                    if (message.timestamp != null)
                      Text(
                        message.timestamp!,
                        style: const TextStyle(color: mutedText, fontSize: 11),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComposerBar extends StatelessWidget {
  const ComposerBar({
    super.key,
    required this.controller,
    required this.buttonLabel,
    required this.hintText,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String buttonLabel;
  final String hintText;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bubbleSurfaceAlt,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: panelBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: panelBackgroundAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.attach_file,
              color: textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              style: const TextStyle(color: textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(color: mutedText, fontSize: 14),
                filled: true,
                fillColor: panelBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: panelBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: primaryBlue),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
