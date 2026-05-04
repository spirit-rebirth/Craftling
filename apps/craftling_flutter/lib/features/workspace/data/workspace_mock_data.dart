import '../domain/workspace_models.dart';

List<TaskWorkspaceData> buildInitialWorkspaceData() {
  return <TaskWorkspaceData>[
    TaskWorkspaceData(
      task: const TaskItemData(
        id: 'task-running-patrol',
        title: 'Refine enemy patrol in Level_A',
        status: TaskStatus.running,
      ),
      phase: TaskPhase.run,
      summaryLine: 'Run phase · 4 workers active · last update 46s ago',
      messages: const <ChatMessageData>[
        ChatMessageData(
          type: MessageType.user,
          text:
              'Please update the enemy patrol logic to use a three-stage path, and test the animations.',
          timestamp: '12:47 PM',
        ),
        ChatMessageData(
          type: MessageType.agent,
          text:
              'Got it. I’ll update the patrol logic to a three-stage path and validate the patrol animations.',
          timestamp: '12:47 PM',
        ),
        ChatMessageData(
          type: MessageType.agent,
          text:
              'I’ve dispatched the task and will notify you once it’s complete. This may include blueprint edits and scene validation.',
          timestamp: '12:48 PM',
        ),
        ChatMessageData(
          type: MessageType.approval,
          title: 'Enemy Patrol Logic Updated & Tested',
          text:
              'The run completed successfully and is ready for your approval.',
          bullets: <String>[
            'Updated blueprint to three-stage path',
            'Patrol transitions validated',
            'Runtime log indicates success',
            'See Key Evidence on the right for logs, screenshot, and test recording',
          ],
          previewLabel: 'Preview\nLevel_A\n12s clip',
          timestamp: '1:10 PM',
        ),
      ],
      workers: const <WorkerItemData>[
        WorkerItemData(name: 'Blueprint Editor', status: TaskStatus.done),
        WorkerItemData(name: 'Scene Validator', status: TaskStatus.done),
        WorkerItemData(name: 'Animation Check', status: TaskStatus.done),
        WorkerItemData(name: 'Evidence Collector', status: TaskStatus.done),
      ],
      evidence: const <EvidenceItemData>[
        EvidenceItemData(
          type: EvidenceType.log,
          title: 'Confirmed "success" appears in runtime log',
          source: 'Scene Validator',
          timeAgo: '2 min ago',
        ),
        EvidenceItemData(
          type: EvidenceType.validation,
          title: 'Patrol transitions completed with no clipping',
          source: 'Animation Check',
          timeAgo: '1 min ago',
        ),
        EvidenceItemData(
          type: EvidenceType.toolOutput,
          title: 'Blueprint compiled successfully with no errors',
          source: 'UE Blueprint Tool',
          timeAgo: '3 min ago',
        ),
        EvidenceItemData(
          type: EvidenceType.screenshot,
          title: 'Updated patrol graph captured after edit',
          source: 'Blueprint Editor',
          timeAgo: '2 min ago',
          hasPreview: true,
        ),
        EvidenceItemData(
          type: EvidenceType.video,
          title: 'Patrol test recording exported from Level_A',
          source: 'Capture Tool',
          timeAgo: '5 min ago',
          hasPreview: true,
        ),
      ],
      overviewRows: const <MapEntry<String, String>>[
        MapEntry<String, String>('Status', 'Running'),
        MapEntry<String, String>('Priority', 'High'),
        MapEntry<String, String>('Assigned to', 'AIAgent'),
        MapEntry<String, String>('Project', 'Gameplay / Level_A'),
        MapEntry<String, String>('Started', '12:45 PM, Today'),
        MapEntry<String, String>('Last Update', '1:10 PM, Today'),
      ],
    ),
    _simpleTask(
      id: 'task-waiting-textures',
      title: 'Optimize character textures',
      status: TaskStatus.waitingForInput,
      phase: TaskPhase.review,
      summary: 'Waiting for input · ready for approval before export',
    ),
    _simpleTask(
      id: 'task-review-spawn',
      title: 'Fix NPC spawn bug',
      status: TaskStatus.pending,
      phase: TaskPhase.merge,
      summary: 'Merge phase · candidate fix prepared for review',
    ),
    _simpleTask(
      id: 'task-complete-lighting',
      title: 'Adjust lighting in scene_02',
      status: TaskStatus.done,
      phase: TaskPhase.review,
      summary: 'Review phase · completed successfully',
    ),
    _simpleTask(
      id: 'task-failed-branch',
      title: 'Build failed on 4.1 branch',
      status: TaskStatus.failed,
      phase: TaskPhase.run,
      summary: 'Run phase · compilation failed during validation',
    ),
  ];
}

TaskWorkspaceData buildNewTaskWorkspaceData({
  required String id,
  required String request,
}) {
  final String cleanRequest = request.trim();
  final String title = _titleFromRequest(cleanRequest);
  return TaskWorkspaceData(
    task: TaskItemData(id: id, title: title, status: TaskStatus.running),
    phase: TaskPhase.run,
    summaryLine: 'Run phase · 4 workers active · task created just now',
    messages: <ChatMessageData>[
      ChatMessageData(
        type: MessageType.user,
        text: cleanRequest,
        timestamp: 'Now',
      ),
      ChatMessageData(
        type: MessageType.agent,
        text:
            'Understood. I’ve created a new task, started execution, and I’ll return results here once the run is ready for review.',
        timestamp: 'Now',
      ),
      ChatMessageData(
        type: MessageType.agent,
        text:
            'The task is now in progress. I’m coordinating edits, validation, and evidence collection in the background.',
        timestamp: 'Now',
      ),
    ],
    workers: const <WorkerItemData>[
      WorkerItemData(name: 'Planner', status: TaskStatus.done),
      WorkerItemData(name: 'Implementation Worker', status: TaskStatus.running),
      WorkerItemData(name: 'Validation Worker', status: TaskStatus.pending),
      WorkerItemData(name: 'Evidence Collector', status: TaskStatus.pending),
    ],
    evidence: const <EvidenceItemData>[
      EvidenceItemData(
        type: EvidenceType.note,
        title: 'Task created and dispatched from the workspace',
        source: 'Main Agent',
        timeAgo: 'just now',
      ),
    ],
    overviewRows: <MapEntry<String, String>>[
      const MapEntry<String, String>('Status', 'Running'),
      const MapEntry<String, String>('Priority', 'High'),
      const MapEntry<String, String>('Assigned to', 'AIAgent'),
      const MapEntry<String, String>('Project', 'Gameplay'),
      const MapEntry<String, String>('Started', 'Just now'),
      const MapEntry<String, String>('Last Update', 'Just now'),
    ],
  );
}

TaskWorkspaceData buildUpdatedTaskWorkspaceData({
  required TaskWorkspaceData base,
  required String followUp,
}) {
  final List<ChatMessageData>
  nextMessages = List<ChatMessageData>.from(base.messages)
    ..add(
      ChatMessageData(
        type: MessageType.user,
        text: followUp.trim(),
        timestamp: 'Now',
      ),
    )
    ..add(
      const ChatMessageData(
        type: MessageType.agent,
        text:
            'Received. I’ve appended the follow-up and continued the task with the updated instruction.',
        timestamp: 'Now',
      ),
    );

  return TaskWorkspaceData(
    task: base.task,
    phase: TaskPhase.run,
    summaryLine:
        'Run phase · task updated with a follow-up · last update just now',
    messages: nextMessages,
    workers: base.workers,
    evidence: base.evidence,
    overviewRows: base.overviewRows
        .map(
          (MapEntry<String, String> row) => row.key == 'Last Update'
              ? const MapEntry<String, String>('Last Update', 'Just now')
              : row,
        )
        .toList(),
  );
}

TaskWorkspaceData buildApprovedTaskWorkspaceData({
  required TaskWorkspaceData base,
}) {
  final List<ChatMessageData> nextMessages =
      base.messages.map((ChatMessageData message) {
        if (message.type != MessageType.approval) {
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
          text: 'Approval received. Marking task as complete.',
          timestamp: 'Now',
        ),
      );

  return TaskWorkspaceData(
    task: TaskItemData(
      id: base.task.id,
      title: base.task.title,
      status: TaskStatus.done,
      subtitle: base.task.subtitle,
    ),
    phase: TaskPhase.review,
    summaryLine: 'Review phase · approval completed · task marked done',
    messages: nextMessages,
    workers: base.workers,
    evidence: base.evidence,
    overviewRows: base.overviewRows
        .map(
          (MapEntry<String, String> row) => switch (row.key) {
            'Status' => const MapEntry<String, String>('Status', 'Done'),
            'Last Update' => const MapEntry<String, String>(
              'Last Update',
              'Just now',
            ),
            _ => row,
          },
        )
        .toList(),
  );
}

TaskWorkspaceData _simpleTask({
  required String id,
  required String title,
  required TaskStatus status,
  required TaskPhase phase,
  required String summary,
}) {
  return TaskWorkspaceData(
    task: TaskItemData(id: id, title: title, status: status),
    phase: phase,
    summaryLine: summary,
    messages: <ChatMessageData>[
      ChatMessageData(
        type: MessageType.agent,
        text: '$title is available as a mocked task entry.',
        timestamp: 'Earlier',
      ),
    ],
    workers: const <WorkerItemData>[
      WorkerItemData(name: 'Main Agent', status: TaskStatus.done),
    ],
    evidence: const <EvidenceItemData>[
      EvidenceItemData(
        type: EvidenceType.note,
        title: 'Mock task entry available in the workspace',
        source: 'Workspace Seed Data',
        timeAgo: 'earlier',
      ),
    ],
    overviewRows: <MapEntry<String, String>>[
      MapEntry<String, String>('Status', _statusLabel(status)),
      const MapEntry<String, String>('Priority', 'Normal'),
      const MapEntry<String, String>('Assigned to', 'AIAgent'),
      const MapEntry<String, String>('Project', 'Gameplay'),
      const MapEntry<String, String>('Started', 'Earlier'),
      const MapEntry<String, String>('Last Update', 'Earlier'),
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

String _statusLabel(TaskStatus status) {
  return switch (status) {
    TaskStatus.running => 'Running',
    TaskStatus.waitingForInput => 'Waiting for Input',
    TaskStatus.pending => 'Pending',
    TaskStatus.done => 'Done',
    TaskStatus.failed => 'Failed',
  };
}
