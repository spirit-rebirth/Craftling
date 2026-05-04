enum TaskPhase { request, plan, dispatch, run, merge, review }

enum TaskStatus { running, waitingForInput, pending, done, failed }

enum EvidenceType { log, validation, toolOutput, screenshot, video, note }

enum MessageType { user, agent, approval }

class TaskItemData {
  const TaskItemData({
    required this.id,
    required this.title,
    required this.status,
    this.subtitle,
  });

  final String id;
  final String title;
  final TaskStatus status;
  final String? subtitle;
}

class ChatMessageData {
  const ChatMessageData({
    required this.type,
    required this.text,
    this.title,
    this.bullets,
    this.previewLabel,
    this.timestamp,
    this.isApproved = false,
    this.approvalStatusText,
  });

  final MessageType type;
  final String text;
  final String? title;
  final List<String>? bullets;
  final String? previewLabel;
  final String? timestamp;
  final bool isApproved;
  final String? approvalStatusText;
}

class EvidenceItemData {
  const EvidenceItemData({
    required this.type,
    required this.title,
    required this.source,
    required this.timeAgo,
    this.id = '',
    this.stage,
    this.text,
    this.assetPath,
    this.hasPreview = false,
  });

  final EvidenceType type;
  final String title;
  final String source;
  final String timeAgo;
  final String id;
  final String? stage;
  final String? text;
  final String? assetPath;
  final bool hasPreview;
}

class WorkerItemData {
  const WorkerItemData({required this.name, required this.status});

  final String name;
  final TaskStatus status;
}

class TaskWorkspaceData {
  const TaskWorkspaceData({
    required this.task,
    required this.phase,
    required this.summaryLine,
    required this.messages,
    required this.workers,
    required this.evidence,
    required this.overviewRows,
  });

  final TaskItemData task;
  final TaskPhase phase;
  final String summaryLine;
  final List<ChatMessageData> messages;
  final List<WorkerItemData> workers;
  final List<EvidenceItemData> evidence;
  final List<MapEntry<String, String>> overviewRows;
}
