import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/widgets/app_sidebar.dart';
import '../../../../core/network/craftling_gateway_url.dart';
import '../../../dashboard/presentation/pages/dashboard_page.dart';
import '../../data/workspace_mock_data.dart';
import '../../domain/workspace_models.dart';
import '../../state/workspace_backend_controller.dart';
import '../theme/workspace_colors.dart';
import '../widgets/task_conversation_panel.dart';
import '../widgets/task_details_sidebar.dart';
import '../widgets/task_list_sidebar.dart';
import '../widgets/workspace_shared.dart';

class TaskWorkspacePage extends StatelessWidget {
  const TaskWorkspacePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TasksPage();
  }
}

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaskWorkspaceScaffold();
  }
}

class TaskWorkspaceScaffold extends StatefulWidget {
  const TaskWorkspaceScaffold({super.key});

  @override
  State<TaskWorkspaceScaffold> createState() => _TaskWorkspaceScaffoldState();
}

class _TaskWorkspaceScaffoldState extends State<TaskWorkspaceScaffold> {
  static const String _assistantPlaceholder =
      'OpenClaw is waiting for the Craftling Gateway response.';

  late final WorkspaceBackendController _backendController;
  StreamSubscription<WorkspaceBackendEvent>? _backendEventSubscription;
  late List<TaskWorkspaceData> _tasks;
  String? _selectedTaskId;
  String _backendServiceUrl = defaultCraftlingGatewayUrl;
  bool _isBackendOnline = false;
  TaskConversationViewMode _centerMode = TaskConversationViewMode.start;
  String _currentSection = 'dashboard';
  int _taskCounter = 0;
  final Map<String, String> _approvalTokensByTaskId = <String, String>{};

  final Map<String, bool> _groupExpanded = <String, bool>{
    'In Progress': true,
    'Pending Approval': true,
    'Completed': true,
  };

  @override
  void initState() {
    super.initState();
    _tasks = <TaskWorkspaceData>[];
    _backendController = WorkspaceBackendController()
      ..addListener(_handleBackendControllerChanged);
    _backendEventSubscription = _backendController.events.listen(
      _handleBackendEvent,
    );
  }

  @override
  void dispose() {
    _backendEventSubscription?.cancel();
    _backendController
      ..removeListener(_handleBackendControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _handleBackendControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBackendOnline = _backendController.connected;
    });
  }

  void _handleBackendEvent(WorkspaceBackendEvent event) {
    final String? taskId = event.taskId;
    if (taskId == null || taskId.isEmpty) {
      return;
    }

    switch (event.type) {
      case WorkspaceBackendEventType.user:
        return;
      case WorkspaceBackendEventType.system:
        _markTaskRunning(taskId, event.message);
      case WorkspaceBackendEventType.stream:
        _appendAssistantDelta(taskId, event.delta ?? '');
      case WorkspaceBackendEventType.finalMessage:
        _resolveAssistantMessage(
          taskId,
          event.message ?? '',
          streamAlreadyDelivered: event.streamAlreadyDelivered,
        );
      case WorkspaceBackendEventType.permission:
        _recordPermissionEvent(taskId, event);
      case WorkspaceBackendEventType.approvalRequired:
        _showApprovalGate(taskId, event);
      case WorkspaceBackendEventType.evidence:
        _appendEvidence(taskId, event);
      case WorkspaceBackendEventType.error:
        _failTask(taskId, event.message ?? 'Backend error.');
    }
  }

  TaskWorkspaceData? get _selectedTask {
    for (final TaskWorkspaceData task in _tasks) {
      if (task.task.id == _selectedTaskId) {
        return task;
      }
    }
    return null;
  }

  TaskWorkspaceData _buildLiveTask({
    required String id,
    required String request,
  }) {
    final String cleanRequest = request.trim();
    final String title = _titleFromRequest(cleanRequest);
    return TaskWorkspaceData(
      task: TaskItemData(id: id, title: title, status: TaskStatus.running),
      phase: TaskPhase.request,
      summaryLine: 'Request phase - waiting for backend execution',
      messages: <ChatMessageData>[
        ChatMessageData(
          type: MessageType.user,
          text: cleanRequest,
          timestamp: 'Now',
        ),
        const ChatMessageData(
          type: MessageType.agent,
          text: _assistantPlaceholder,
          timestamp: 'Now',
        ),
      ],
      workers: const <WorkerItemData>[
        WorkerItemData(name: 'Main Agent', status: TaskStatus.running),
      ],
      evidence: const <EvidenceItemData>[],
      overviewRows: const <MapEntry<String, String>>[
        MapEntry<String, String>('Status', 'Running'),
        MapEntry<String, String>('Priority', 'High'),
        MapEntry<String, String>('Assigned to', 'Main Agent'),
        MapEntry<String, String>('Project', 'Workspace'),
        MapEntry<String, String>('Started', 'Just now'),
        MapEntry<String, String>('Last Update', 'Just now'),
      ],
    );
  }

  String _titleFromRequest(String request) {
    final String trimmed = request.trim();
    if (trimmed.isEmpty) {
      return 'New task';
    }
    if (trimmed.length <= 48) {
      return trimmed;
    }
    return '${trimmed.substring(0, 45)}...';
  }

  void _replaceTask(
    String taskId,
    TaskWorkspaceData Function(TaskWorkspaceData task) update,
  ) {
    setState(() {
      _tasks = _tasks
          .map(
            (TaskWorkspaceData task) =>
                task.task.id == taskId ? update(task) : task,
          )
          .toList();
    });
  }

  TaskWorkspaceData _copyTaskWorkspace(
    TaskWorkspaceData base, {
    TaskItemData? task,
    TaskPhase? phase,
    String? summaryLine,
    List<ChatMessageData>? messages,
    List<WorkerItemData>? workers,
    List<EvidenceItemData>? evidence,
    List<MapEntry<String, String>>? overviewRows,
  }) {
    return TaskWorkspaceData(
      task: task ?? base.task,
      phase: phase ?? base.phase,
      summaryLine: summaryLine ?? base.summaryLine,
      messages: messages ?? base.messages,
      workers: workers ?? base.workers,
      evidence: evidence ?? base.evidence,
      overviewRows: overviewRows ?? base.overviewRows,
    );
  }

  TaskItemData _taskWithStatus(TaskItemData base, TaskStatus status) {
    return TaskItemData(
      id: base.id,
      title: base.title,
      status: status,
      subtitle: base.subtitle,
    );
  }

  List<MapEntry<String, String>> _overviewWithStatus(
    List<MapEntry<String, String>> rows,
    String status,
  ) {
    return rows
        .map(
          (MapEntry<String, String> row) => switch (row.key) {
            'Status' => MapEntry<String, String>('Status', status),
            'Last Update' => const MapEntry<String, String>(
              'Last Update',
              'Just now',
            ),
            _ => row,
          },
        )
        .toList();
  }

  bool _isPendingAssistantText(String text) {
    return text == _assistantPlaceholder ||
        text.startsWith('OpenClaw is thinking...');
  }

  ChatMessageData _agentMessage(String text) {
    return ChatMessageData(
      type: MessageType.agent,
      text: text,
      timestamp: 'Now',
    );
  }

  List<EvidenceItemData> _evidenceFromFinalMessage(String message) {
    final List<String> lines = message.replaceAll('\r\n', '\n').split('\n');
    final int start = lines.indexWhere((String line) {
      final String normalized = line.trim().toLowerCase();
      return normalized.startsWith('关键运行证据') ||
          normalized.startsWith('关键证据') ||
          normalized.startsWith('运行证据') ||
          normalized.startsWith('key evidence') ||
          normalized.startsWith('evidence');
    });
    if (start < 0) {
      return const <EvidenceItemData>[];
    }

    final List<EvidenceItemData> items = <EvidenceItemData>[];
    String? currentTitle;
    void addCurrentTitleAsItem() {
      final String? title = currentTitle;
      if (title == null || title.isEmpty) {
        return;
      }
      items.add(
        EvidenceItemData(
          type: _evidenceTypeFor(title, title),
          title: title,
          source: title,
          timeAgo: 'just now',
        ),
      );
      currentTitle = null;
    }

    for (final String rawLine in lines.skip(start + 1)) {
      final String trimmed = rawLine.trimRight();
      final String normalized = trimmed.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (!normalized.startsWith('- ') &&
          (normalized.endsWith('：') || normalized.endsWith(':'))) {
        addCurrentTitleAsItem();
        break;
      }

      if (trimmed.startsWith('- ')) {
        addCurrentTitleAsItem();
        final String evidenceLine = normalized.substring(2).trim();
        final int colonIndex = evidenceLine.indexOf(RegExp(r'[:：]'));
        if (colonIndex > 0 && colonIndex < evidenceLine.length - 1) {
          final String title = evidenceLine.substring(0, colonIndex).trim();
          final String detail = evidenceLine.substring(colonIndex + 1).trim();
          items.add(
            EvidenceItemData(
              type: _evidenceTypeFor(title, detail),
              title: title,
              source: detail,
              timeAgo: 'just now',
            ),
          );
          currentTitle = null;
        } else {
          currentTitle = evidenceLine;
        }
        continue;
      }

      if (trimmed.startsWith('  - ') && currentTitle != null) {
        final String title = currentTitle!;
        final String detail = normalized.substring(2).trim();
        items.add(
          EvidenceItemData(
            type: _evidenceTypeFor(title, detail),
            title: title,
            source: detail,
            timeAgo: 'just now',
          ),
        );
        currentTitle = null;
      }
    }
    addCurrentTitleAsItem();
    return items;
  }

  EvidenceType _evidenceTypeFor(String title, String detail) {
    final String haystack = '$title $detail'.toLowerCase();
    if (haystack.contains('[agenttest]') ||
        haystack.contains('log') ||
        title.contains('日志')) {
      return EvidenceType.log;
    }
    if (haystack.contains('spawned actor') || title.contains('放置')) {
      return EvidenceType.toolOutput;
    }
    if (haystack.contains('/script/') || title.contains('类识别')) {
      return EvidenceType.validation;
    }
    return EvidenceType.note;
  }

  EvidenceType _evidenceTypeFromKind(String? kind, String title, String detail) {
    return switch (kind) {
      'log' => EvidenceType.log,
      'validation' => EvidenceType.validation,
      'toolOutput' => EvidenceType.toolOutput,
      'screenshot' => EvidenceType.screenshot,
      'video' => EvidenceType.video,
      'note' => EvidenceType.note,
      _ => _evidenceTypeFor(title, detail),
    };
  }

  String? _evidenceAssetPath(String? path) {
    final String value = path?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    if (!value.startsWith('/')) {
      return value;
    }
    final String baseUrl = _backendServiceUrl.endsWith('/')
        ? _backendServiceUrl.substring(0, _backendServiceUrl.length - 1)
        : _backendServiceUrl;
    return '$baseUrl$value';
  }

  List<ChatMessageData> _messagesWithAssistantContent(
    TaskWorkspaceData task,
    String content, {
    required bool append,
  }) {
    final List<ChatMessageData> messages = List<ChatMessageData>.from(
      task.messages,
    );
    if (messages.isEmpty || messages.last.type != MessageType.agent) {
      messages.add(_agentMessage(content));
      return messages;
    }

    final ChatMessageData last = messages.last;
    final String nextText = append && !_isPendingAssistantText(last.text)
        ? '${last.text}$content'
        : content;
    messages[messages.length - 1] = ChatMessageData(
      type: last.type,
      text: nextText,
      title: last.title,
      bullets: last.bullets,
      previewLabel: last.previewLabel,
      timestamp: last.timestamp,
      isApproved: last.isApproved,
      approvalStatusText: last.approvalStatusText,
    );
    return messages;
  }

  List<ChatMessageData> _messagesWithFailureContent(
    TaskWorkspaceData task,
    String message,
  ) {
    final List<ChatMessageData> messages = List<ChatMessageData>.from(
      task.messages,
    );
    if (messages.isEmpty || messages.last.type != MessageType.agent) {
      messages.add(_agentMessage(message));
      return messages;
    }

    final ChatMessageData last = messages.last;
    if (_isPendingAssistantText(last.text)) {
      messages[messages.length - 1] = ChatMessageData(
        type: last.type,
        text: message,
        title: last.title,
        bullets: last.bullets,
        previewLabel: last.previewLabel,
        timestamp: last.timestamp,
        isApproved: last.isApproved,
        approvalStatusText: last.approvalStatusText,
      );
      return messages;
    }

    messages.add(_agentMessage(message));
    return messages;
  }

  void _markTaskRunning(String taskId, String? message) {
    _replaceTask(taskId, (TaskWorkspaceData task) {
      final List<ChatMessageData> messages = message == null
          ? task.messages
          : _messagesWithAssistantContent(task, message, append: false);
      return _copyTaskWorkspace(
        task,
        task: _taskWithStatus(task.task, TaskStatus.running),
        phase: TaskPhase.run,
        summaryLine: 'Run phase - OpenClaw is working',
        messages: messages,
        workers: const <WorkerItemData>[
          WorkerItemData(name: 'Main Agent', status: TaskStatus.running),
        ],
        overviewRows: _overviewWithStatus(task.overviewRows, 'Running'),
      );
    });
  }

  void _appendAssistantDelta(String taskId, String delta) {
    if (delta.isEmpty) {
      return;
    }
    _replaceTask(taskId, (TaskWorkspaceData task) {
      return _copyTaskWorkspace(
        task,
        task: _taskWithStatus(task.task, TaskStatus.running),
        phase: TaskPhase.run,
        summaryLine: 'Run phase - streaming OpenClaw response',
        messages: _messagesWithAssistantContent(task, delta, append: true),
        overviewRows: _overviewWithStatus(task.overviewRows, 'Running'),
      );
    });
  }

  void _resolveAssistantMessage(
    String taskId,
    String message, {
    required bool streamAlreadyDelivered,
  }) {
    if (message.startsWith('OpenClaw call failed:') ||
        message == 'OpenClaw request timed out.') {
      _failTask(taskId, message);
      return;
    }

    _replaceTask(taskId, (TaskWorkspaceData task) {
      return _copyTaskWorkspace(
        task,
        task: _taskWithStatus(task.task, TaskStatus.done),
        phase: TaskPhase.review,
        summaryLine: 'Review phase - OpenClaw returned a final reply',
        messages: streamAlreadyDelivered
            ? task.messages
            : _messagesWithAssistantContent(task, message, append: false),
        workers: const <WorkerItemData>[
          WorkerItemData(name: 'Main Agent', status: TaskStatus.done),
        ],
        evidence: <EvidenceItemData>[
          ...task.evidence,
          ..._evidenceFromFinalMessage(message),
        ],
        overviewRows: _overviewWithStatus(task.overviewRows, 'Done'),
      );
    });
  }

  void _recordPermissionEvent(String taskId, WorkspaceBackendEvent event) {
    // Permission events are not verification evidence. Approval gates are
    // represented in the conversation instead of the evidence sidebar.
  }

  void _appendEvidence(String taskId, WorkspaceBackendEvent event) {
    final String title = event.evidenceTitle?.trim().isNotEmpty == true
        ? event.evidenceTitle!.trim()
        : event.evidenceStage?.trim().isNotEmpty == true
            ? event.evidenceStage!.trim()
            : 'Evidence';
    final String text = event.evidenceText?.trim() ?? '';
    final String source = event.evidenceSource?.trim().isNotEmpty == true
        ? event.evidenceSource!.trim()
        : 'OpenClaw';
    final String? assetPath = _evidenceAssetPath(event.evidenceAssetPath);
    final EvidenceItemData item = EvidenceItemData(
      id: event.evidenceId ?? '',
      type: _evidenceTypeFromKind(event.evidenceKind, title, text),
      title: title,
      source: source,
      timeAgo: event.evidenceTimeAgo ?? 'just now',
      stage: event.evidenceStage,
      text: text,
      assetPath: assetPath,
      hasPreview: assetPath != null,
    );

    _replaceTask(taskId, (TaskWorkspaceData task) {
      if (item.id.isNotEmpty &&
          task.evidence.any((EvidenceItemData existing) => existing.id == item.id)) {
        return task;
      }

      return _copyTaskWorkspace(
        task,
        evidence: <EvidenceItemData>[...task.evidence, item],
        overviewRows: _overviewWithStatus(task.overviewRows, 'Running'),
      );
    });
  }

  void _showApprovalGate(String taskId, WorkspaceBackendEvent event) {
    final String? resumeToken = event.resumeToken;
    if (resumeToken == null || resumeToken.isEmpty) {
      _failTask(taskId, 'Backend approval request is missing a resume token.');
      return;
    }

    _approvalTokensByTaskId[taskId] = resumeToken;
    _replaceTask(taskId, (TaskWorkspaceData task) {
      return _copyTaskWorkspace(
        task,
        task: _taskWithStatus(task.task, TaskStatus.pending),
        phase: TaskPhase.review,
        summaryLine: 'Review phase - approval required',
        messages: <ChatMessageData>[
          ...task.messages,
          ChatMessageData(
            type: MessageType.approval,
            title: 'Approval Required',
            text: event.message ?? 'Review and approve this workflow gate.',
            bullets: const <String>[
              'The deterministic Unreal workflow is paused.',
              'Approve to resume the lobster pipeline.',
            ],
            previewLabel: 'Lobster\nGate',
            timestamp: 'Now',
          ),
        ],
        workers: const <WorkerItemData>[
          WorkerItemData(name: 'Main Agent', status: TaskStatus.pending),
        ],
        overviewRows: _overviewWithStatus(task.overviewRows, 'Pending'),
      );
    });
  }

  void _failTask(String taskId, String message) {
    _replaceTask(taskId, (TaskWorkspaceData task) {
      return _copyTaskWorkspace(
        task,
        task: _taskWithStatus(task.task, TaskStatus.failed),
        phase: TaskPhase.review,
        summaryLine: 'Review phase - backend request failed',
        messages: _messagesWithFailureContent(task, message),
        workers: const <WorkerItemData>[
          WorkerItemData(name: 'Main Agent', status: TaskStatus.failed),
        ],
        evidence: <EvidenceItemData>[
          ...task.evidence,
          EvidenceItemData(
            type: EvidenceType.log,
            title: message,
            source: 'Backend relay',
            timeAgo: 'just now',
          ),
        ],
        overviewRows: _overviewWithStatus(task.overviewRows, 'Failed'),
      );
    });
  }

  void _selectTask(String taskId) {
    setState(() {
      _selectedTaskId = taskId;
      _currentSection = 'tasks';
      _centerMode = TaskConversationViewMode.task;
    });
  }

  void _startNewTaskFlow() {
    setState(() {
      _selectedTaskId = null;
      _currentSection = 'tasks';
      _centerMode = TaskConversationViewMode.start;
      _groupExpanded['In Progress'] = true;
    });
  }

  void _toggleGroup(String groupTitle) {
    setState(() {
      _groupExpanded[groupTitle] = !(_groupExpanded[groupTitle] ?? true);
    });
  }

  void _createTask(String request) {
    final String trimmed = request.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final int createdAt = DateTime.now().microsecondsSinceEpoch;
    final TaskWorkspaceData created = _buildLiveTask(
      id: 'task-$createdAt-${_taskCounter++}',
      request: trimmed,
    );

    setState(() {
      _tasks = <TaskWorkspaceData>[created, ..._tasks];
      _selectedTaskId = created.task.id;
      _currentSection = 'tasks';
      _centerMode = TaskConversationViewMode.task;
      _groupExpanded['In Progress'] = true;
    });

    final bool sent = _backendController.sendTaskMessage(
      taskId: created.task.id,
      message: trimmed,
    );
    if (!sent) {
      _failTask(
        created.task.id,
        'Craftling Gateway is offline. Connect in Settings first.',
      );
    }
  }

  void _appendFollowUp(String text) {
    final String trimmed = text.trim();
    final TaskWorkspaceData? selected = _selectedTask;
    if (trimmed.isEmpty || selected == null) {
      return;
    }

    _replaceTask(selected.task.id, (TaskWorkspaceData task) {
      return _copyTaskWorkspace(
        task,
        task: _taskWithStatus(task.task, TaskStatus.running),
        phase: TaskPhase.request,
        summaryLine: 'Request phase - follow-up queued for backend execution',
        messages: <ChatMessageData>[
          ...task.messages,
          ChatMessageData(
            type: MessageType.user,
            text: trimmed,
            timestamp: 'Now',
          ),
          const ChatMessageData(
            type: MessageType.agent,
            text: _assistantPlaceholder,
            timestamp: 'Now',
          ),
        ],
        workers: const <WorkerItemData>[
          WorkerItemData(name: 'Main Agent', status: TaskStatus.running),
        ],
        overviewRows: _overviewWithStatus(task.overviewRows, 'Running'),
      );
    });

    final bool sent = _backendController.sendTaskMessage(
      taskId: selected.task.id,
      message: trimmed,
    );
    if (!sent) {
      _failTask(
        selected.task.id,
        'Craftling Gateway is offline. Connect in Settings first.',
      );
    }
  }

  void _deleteTask(String taskId) {
    setState(() {
      _tasks = _tasks
          .where((TaskWorkspaceData task) => task.task.id != taskId)
          .toList();
      if (_selectedTaskId == taskId) {
        _selectedTaskId = null;
        _currentSection = 'tasks';
        _centerMode = TaskConversationViewMode.start;
      }
    });
  }

  void _pinTaskToTop(String taskId) {
    final int index = _tasks.indexWhere(
      (TaskWorkspaceData task) => task.task.id == taskId,
    );
    if (index <= 0) {
      return;
    }

    setState(() {
      final TaskWorkspaceData task = _tasks.removeAt(index);
      _tasks.insert(0, task);
    });
  }

  Future<void> _renameTask(String taskId) async {
    final TaskWorkspaceData? target = _tasks
        .cast<TaskWorkspaceData?>()
        .firstWhere(
          (TaskWorkspaceData? task) => task?.task.id == taskId,
          orElse: () => null,
        );
    if (target == null) {
      return;
    }

    final TextEditingController controller = TextEditingController(
      text: target.task.title,
    );
    final String? nextTitle = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xB3141C29),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: panelBackground,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: panelBorder),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x36000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Rename Task',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Task title',
                    hintStyle: const TextStyle(color: mutedText, fontSize: 14),
                    filled: true,
                    fillColor: bubbleSurfaceAlt,
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
                  onSubmitted: (String value) =>
                      Navigator.of(context).pop(value.trim()),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: textSecondary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(controller.text.trim()),
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();

    final String trimmed = nextTitle?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == target.task.title) {
      return;
    }

    setState(() {
      _tasks = _tasks.map((TaskWorkspaceData task) {
        if (task.task.id != taskId) {
          return task;
        }
        return TaskWorkspaceData(
          task: TaskItemData(
            id: task.task.id,
            title: trimmed,
            status: task.task.status,
            subtitle: task.task.subtitle,
          ),
          phase: task.phase,
          summaryLine: task.summaryLine,
          messages: task.messages,
          workers: task.workers,
          evidence: task.evidence,
          overviewRows: task.overviewRows,
        );
      }).toList();
    });
  }

  void _exitTaskView() {
    setState(() {
      _selectedTaskId = null;
      _currentSection = 'tasks';
      _centerMode = TaskConversationViewMode.start;
    });
  }

  void _approveSelectedTask() {
    final TaskWorkspaceData? selected = _selectedTask;
    if (selected == null) {
      return;
    }
    _approveTask(selected.task.id);
  }

  void _approveTask(String taskId) {
    final String? resumeToken = _approvalTokensByTaskId.remove(taskId);
    if (resumeToken == null || resumeToken.isEmpty) {
      final TaskWorkspaceData? target = _tasks
          .cast<TaskWorkspaceData?>()
          .firstWhere(
            (TaskWorkspaceData? task) => task?.task.id == taskId,
            orElse: () => null,
          );
      if (target == null) {
        return;
      }

      final TaskWorkspaceData updated = buildApprovedTaskWorkspaceData(
        base: target,
      );
      setState(() {
        _tasks = _tasks
            .map(
              (TaskWorkspaceData task) =>
                  task.task.id == updated.task.id ? updated : task,
            )
            .toList();
      });
      return;
    }

    final bool sent = _backendController.sendApproval(
      taskId: taskId,
      resumeToken: resumeToken,
      approve: true,
    );
    if (!sent) {
      _failTask(
        taskId,
        'Craftling Gateway is offline. Reconnect before approving.',
      );
      return;
    }

    _replaceTask(taskId, (TaskWorkspaceData task) {
      final List<ChatMessageData> messages =
          task.messages.map((ChatMessageData message) {
            if (message.type != MessageType.approval || message.isApproved) {
              return message;
            }
            return ChatMessageData(
              type: message.type,
              text: message.text,
              title: message.title,
              bullets: message.bullets,
              previewLabel: message.previewLabel,
              timestamp: message.timestamp,
              isApproved: true,
              approvalStatusText: 'Approved by user',
            );
          }).toList()..add(
            const ChatMessageData(
              type: MessageType.agent,
              text: 'Approval sent. Resuming the lobster workflow.',
              timestamp: 'Now',
            ),
          );
      return _copyTaskWorkspace(
        task,
        task: _taskWithStatus(task.task, TaskStatus.running),
        phase: TaskPhase.run,
        summaryLine: 'Run phase - approval sent, resuming workflow',
        messages: messages,
        workers: const <WorkerItemData>[
          WorkerItemData(name: 'Main Agent', status: TaskStatus.running),
        ],
        overviewRows: _overviewWithStatus(task.overviewRows, 'Running'),
      );
    });
  }

  void _openSettingsPage() {
    setState(() {
      _selectedTaskId = null;
      _currentSection = 'settings';
      _centerMode = TaskConversationViewMode.settings;
    });
  }

  void _openUsagePage() {
    setState(() {
      _selectedTaskId = null;
      _currentSection = 'usage';
      _centerMode = TaskConversationViewMode.usage;
    });
  }

  void _saveBackendServiceUrl(String nextValue) {
    final String trimmed = nextValue.trim();
    if (trimmed.isEmpty) {
      return;
    }

    setState(() {
      _backendServiceUrl = trimmed;
    });
  }

  void _setBackendConnectionState(bool isOnline) {
    if (isOnline) {
      _backendController.connect(_backendServiceUrl);
      return;
    }
    _backendController.disconnect();
  }

  List<TaskWorkspaceData> _tasksForStatuses(Set<TaskStatus> statuses) {
    return _tasks
        .where((TaskWorkspaceData task) => statuses.contains(task.task.status))
        .toList();
  }

  List<TaskWorkspaceData> _inProgressTasks() {
    return _tasksForStatuses(<TaskStatus>{
      TaskStatus.running,
      TaskStatus.waitingForInput,
    });
  }

  List<TaskWorkspaceData> _pendingApprovalTasks() {
    return _tasksForStatuses(<TaskStatus>{TaskStatus.pending});
  }

  List<TaskWorkspaceData> _completedTasks() {
    return _tasksForStatuses(<TaskStatus>{TaskStatus.done});
  }

  void _openDashboard() {
    setState(() {
      _selectedTaskId = null;
      _currentSection = 'dashboard';
    });
  }

  void _openTasksRoot() {
    setState(() {
      _selectedTaskId = null;
      _currentSection = 'tasks';
      _centerMode = TaskConversationViewMode.start;
      _groupExpanded['In Progress'] = true;
    });
  }

  void _openPlaceholderSection(String section) {
    setState(() {
      _selectedTaskId = null;
      _currentSection = section;
    });
  }

  Widget _buildContentArea() {
    return switch (_currentSection) {
      'dashboard' => DashboardContent(
        activeTasks: _tasksForStatuses(<TaskStatus>{TaskStatus.running}),
        attentionTasks: _pendingApprovalTasks(),
        onOpenTask: _selectTask,
        onApproveTask: _approveTask,
        onOpenTasks: _openTasksRoot,
        onOpenInbox: () => _openPlaceholderSection('inbox'),
        onOpenAgents: () => _openPlaceholderSection('agents'),
        onOpenWorkspace: () => _openPlaceholderSection('workspace'),
      ),
      'tasks' => Row(
        children: <Widget>[
          Expanded(
            child: TaskWorkspacePanel(
              child: TaskConversationPanel(
                viewMode: _centerMode,
                selectedTask: _selectedTask,
                backendServiceUrl: _backendServiceUrl,
                isBackendOnline: _isBackendOnline,
                inProgressTasks: _inProgressTasks(),
                pendingApprovalTasks: _pendingApprovalTasks(),
                completedTasks: _completedTasks(),
                onStartTask: _createTask,
                onContinueTask: _appendFollowUp,
                onTaskSelected: _selectTask,
                onPinTask: _pinTaskToTop,
                onRenameTask: _renameTask,
                onDeleteTask: _deleteTask,
                onBack: _exitTaskView,
                onApprove: _approveSelectedTask,
                onBackendServiceUrlChanged: _saveBackendServiceUrl,
                onBackendConnectionStateChanged: _setBackendConnectionState,
              ),
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 340,
            child: TaskDetailsPanel(
              child: TaskDetailsSidebar(selectedTask: _selectedTask),
            ),
          ),
        ],
      ),
      'settings' || 'usage' => TaskWorkspacePanel(
        child: TaskConversationPanel(
          viewMode: _centerMode,
          selectedTask: null,
          backendServiceUrl: _backendServiceUrl,
          isBackendOnline: _isBackendOnline,
          inProgressTasks: const <TaskWorkspaceData>[],
          pendingApprovalTasks: const <TaskWorkspaceData>[],
          completedTasks: const <TaskWorkspaceData>[],
          onStartTask: _createTask,
          onContinueTask: _appendFollowUp,
          onTaskSelected: _selectTask,
          onPinTask: _pinTaskToTop,
          onRenameTask: _renameTask,
          onDeleteTask: _deleteTask,
          onBack: _openDashboard,
          onApprove: _approveSelectedTask,
          onBackendServiceUrlChanged: _saveBackendServiceUrl,
          onBackendConnectionStateChanged: _setBackendConnectionState,
        ),
      ),
      'inbox' => const _ShellPlaceholderContent(
        title: 'Inbox',
        message: 'Approvals, replies, and task updates will be collected here.',
        icon: Icons.inbox_rounded,
      ),
      'agents' => const _ShellPlaceholderContent(
        title: 'Agents',
        message:
            'Agent configuration and runtime status will be available here.',
        icon: Icons.smart_toy_rounded,
      ),
      'workspace' => const _ShellPlaceholderContent(
        title: 'Workspace',
        message:
            'Shared project context and working files will be available here.',
        icon: Icons.view_quilt_rounded,
      ),
      'help' => const _ShellPlaceholderContent(
        title: 'Help',
        message: 'Product guidance and support links will live here.',
        icon: Icons.help_outline_rounded,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              AppSidebar(
                currentSection: _currentSection,
                onOpenDashboard: _openDashboard,
                onOpenTasks: _openTasksRoot,
                onOpenInbox: () => _openPlaceholderSection('inbox'),
                onOpenAgents: () => _openPlaceholderSection('agents'),
                onOpenWorkspace: () => _openPlaceholderSection('workspace'),
                onOpenUsage: _openUsagePage,
                onOpenSettings: _openSettingsPage,
                onOpenHelp: () => _openPlaceholderSection('help'),
                taskListContent: TaskListPanel(
                  child: _TaskSidebarHolder(
                    selectedTaskId: _selectedTaskId,
                    inProgressTasks: _inProgressTasks(),
                    pendingApprovalTasks: _pendingApprovalTasks(),
                    completedTasks: _completedTasks(),
                    groupExpanded: _groupExpanded,
                    onNewTask: _startNewTaskFlow,
                    onTaskSelected: _selectTask,
                    onToggleGroup: _toggleGroup,
                    onPinTask: _pinTaskToTop,
                    onRenameTask: _renameTask,
                    onDeleteTask: _deleteTask,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: _buildContentArea()),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskListPanel extends StatelessWidget {
  const TaskListPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class TaskWorkspacePanel extends StatelessWidget {
  const TaskWorkspacePanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class TaskDetailsPanel extends StatelessWidget {
  const TaskDetailsPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class _TaskSidebarHolder extends StatelessWidget {
  const _TaskSidebarHolder({
    required this.selectedTaskId,
    required this.inProgressTasks,
    required this.pendingApprovalTasks,
    required this.completedTasks,
    required this.groupExpanded,
    required this.onNewTask,
    required this.onTaskSelected,
    required this.onToggleGroup,
    required this.onPinTask,
    required this.onRenameTask,
    required this.onDeleteTask,
  });

  final String? selectedTaskId;
  final List<TaskWorkspaceData> inProgressTasks;
  final List<TaskWorkspaceData> pendingApprovalTasks;
  final List<TaskWorkspaceData> completedTasks;
  final Map<String, bool> groupExpanded;
  final VoidCallback onNewTask;
  final ValueChanged<String> onTaskSelected;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<String> onPinTask;
  final ValueChanged<String> onRenameTask;
  final ValueChanged<String> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onNewTask,
              style: TextButton.styleFrom(
                foregroundColor: textPrimary,
                backgroundColor: primaryBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                alignment: Alignment.centerLeft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Task'),
            ),
          ),
          const SizedBox(height: 10),
          Column(
            children: <Widget>[
              SidebarTaskGroup(
                title: 'In Progress',
                items: inProgressTasks,
                selectedTaskId: selectedTaskId,
                isExpanded: groupExpanded['In Progress'] ?? true,
                onToggle: () => onToggleGroup('In Progress'),
                onTaskSelected: onTaskSelected,
                onPinTask: onPinTask,
                onRenameTask: onRenameTask,
                onDeleteTask: onDeleteTask,
              ),
              SidebarTaskGroup(
                title: 'Pending Approval',
                items: pendingApprovalTasks,
                selectedTaskId: selectedTaskId,
                isExpanded: groupExpanded['Pending Approval'] ?? true,
                onToggle: () => onToggleGroup('Pending Approval'),
                onTaskSelected: onTaskSelected,
                onPinTask: onPinTask,
                onRenameTask: onRenameTask,
                onDeleteTask: onDeleteTask,
              ),
              SidebarTaskGroup(
                title: 'Completed',
                items: completedTasks,
                selectedTaskId: selectedTaskId,
                isExpanded: groupExpanded['Completed'] ?? true,
                onToggle: () => onToggleGroup('Completed'),
                onTaskSelected: onTaskSelected,
                onPinTask: onPinTask,
                onRenameTask: onRenameTask,
                onDeleteTask: onDeleteTask,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShellPlaceholderContent extends StatelessWidget {
  const _ShellPlaceholderContent({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: textSecondary, size: 40),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
