import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/network/craftling_gateway_url.dart';

enum WorkspaceBackendEventType {
  user,
  system,
  stream,
  finalMessage,
  permission,
  approvalRequired,
  evidence,
  error,
}

class WorkspaceBackendEvent {
  const WorkspaceBackendEvent({
    required this.type,
    this.taskId,
    this.sessionId,
    this.message,
    this.delta,
    this.tool,
    this.resumeToken,
    this.streamAlreadyDelivered = false,
    this.ok,
    this.status,
    this.evidenceId,
    this.evidenceKind,
    this.evidenceTitle,
    this.evidenceText,
    this.evidenceSource,
    this.evidenceStage,
    this.evidenceAssetPath,
    this.evidenceTimeAgo,
  });

  final WorkspaceBackendEventType type;
  final String? taskId;
  final String? sessionId;
  final String? message;
  final String? delta;
  final String? tool;
  final String? resumeToken;
  final bool streamAlreadyDelivered;
  final bool? ok;
  final String? status;
  final String? evidenceId;
  final String? evidenceKind;
  final String? evidenceTitle;
  final String? evidenceText;
  final String? evidenceSource;
  final String? evidenceStage;
  final String? evidenceAssetPath;
  final String? evidenceTimeAgo;
}

class WorkspaceBackendController extends ChangeNotifier {
  final StreamController<WorkspaceBackendEvent> _events =
      StreamController<WorkspaceBackendEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  bool _connected = false;
  String? _statusMessage;

  Stream<WorkspaceBackendEvent> get events => _events.stream;
  bool get connected => _connected;
  String? get statusMessage => _statusMessage;

  @override
  void dispose() {
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _events.close();
    super.dispose();
  }

  void connect(String input) {
    final String trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      _setOffline('Gateway URL is required.');
      return;
    }

    final String? wsUrl = _toWebSocketUrl(trimmedInput);
    if (wsUrl == null) {
      _setOffline(
        'Gateway URL must start with http://, https://, ws://, or wss://',
      );
      return;
    }

    _channelSubscription?.cancel();
    _channel?.sink.close();

    try {
      final WebSocketChannel nextChannel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );
      _channel = nextChannel;
      _connected = false;
      _statusMessage = 'Connecting to $wsUrl';
      notifyListeners();

      nextChannel.ready
          .then((_) {
            if (_channel != nextChannel) {
              return;
            }
            _connected = true;
            _statusMessage = 'Connected to $wsUrl';
            notifyListeners();
          })
          .catchError((Object error) {
            if (_channel == nextChannel) {
              _setOffline('Connection failed: $error');
            }
          });

      _channelSubscription = nextChannel.stream.listen(
        _handleSocketData,
        onError: (Object error) {
          _setOffline('WebSocket error: $error');
        },
        onDone: () {
          _setOffline('Connection closed');
        },
      );
    } catch (error) {
      _setOffline('Connection failed: $error');
    }
  }

  void disconnect() {
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _channelSubscription = null;
    _channel = null;
    _setOffline('Disconnected from Craftling Gateway.');
  }

  bool sendApproval({
    required String taskId,
    required String resumeToken,
    required bool approve,
  }) {
    if (resumeToken.trim().isEmpty || !_connected) {
      return false;
    }

    try {
      _channel?.sink.add(
        json.encode(<String, Object>{
          'type': 'approval',
          'taskId': taskId,
          'resumeToken': resumeToken.trim(),
          'approve': approve,
        }),
      );
      return true;
    } catch (error) {
      _events.add(
        WorkspaceBackendEvent(
          type: WorkspaceBackendEventType.error,
          taskId: taskId,
          message: 'Approval failed: $error',
        ),
      );
      return false;
    }
  }

  bool sendTaskMessage({required String taskId, required String message}) {
    final String trimmed = message.trim();
    if (trimmed.isEmpty || !_connected) {
      return false;
    }

    try {
      _channel?.sink.add(
        json.encode(<String, String>{
          'type': 'task_message',
          'taskId': taskId,
          'message': trimmed,
        }),
      );
      return true;
    } catch (error) {
      _events.add(
        WorkspaceBackendEvent(
          type: WorkspaceBackendEventType.error,
          taskId: taskId,
          message: 'Send failed: $error',
        ),
      );
      return false;
    }
  }

  String? _toWebSocketUrl(String input) {
    return toCraftlingGatewayWebSocketUrl(input);
  }

  void _handleSocketData(dynamic data) {
    try {
      final Map<String, dynamic> jsonData =
          json.decode(data.toString()) as Map<String, dynamic>;
      final String? type = jsonData['type'] as String?;
      final String? message = jsonData['message'] as String?;
      final String? delta = jsonData['delta'] as String?;
      final String? taskId = jsonData['taskId'] as String?;
      final String? sessionId = jsonData['sessionId'] as String?;
      final String? tool = jsonData['tool'] as String?;
      final String? resumeToken = jsonData['resumeToken'] as String?;
      final bool? ok = jsonData['ok'] as bool?;
      final String? status = jsonData['status'] as String?;
      final String? evidenceId = jsonData['evidenceId'] as String?;
      final String? evidenceKind = jsonData['kind'] as String?;
      final String? evidenceTitle = jsonData['title'] as String?;
      final String? evidenceText = jsonData['text'] as String?;
      final String? evidenceSource = jsonData['source'] as String?;
      final String? evidenceStage = jsonData['stage'] as String?;
      final String? evidenceAssetPath = jsonData['assetPath'] as String?;
      final String? evidenceTimeAgo = jsonData['timeAgo'] as String?;
      final bool streamAlreadyDelivered =
          jsonData['streamAlreadyDelivered'] == true;

      switch (type) {
        case 'user':
          _events.add(
            WorkspaceBackendEvent(
              type: WorkspaceBackendEventType.user,
              taskId: taskId,
              sessionId: sessionId,
              message: message,
            ),
          );
        case 'system':
          _events.add(
            WorkspaceBackendEvent(
              type: _isErrorMessage(message)
                  ? WorkspaceBackendEventType.error
                  : WorkspaceBackendEventType.system,
              taskId: taskId,
              sessionId: sessionId,
              message: message,
            ),
          );
        case 'stream':
          _events.add(
            WorkspaceBackendEvent(
              type: WorkspaceBackendEventType.stream,
              taskId: taskId,
              sessionId: sessionId,
              delta: delta,
            ),
          );
        case 'permission':
          _events.add(
            WorkspaceBackendEvent(
              type: WorkspaceBackendEventType.permission,
              taskId: taskId,
              sessionId: sessionId,
              message: message,
              tool: tool,
            ),
          );
        case 'approval_required':
          _events.add(
            WorkspaceBackendEvent(
              type: WorkspaceBackendEventType.approvalRequired,
              taskId: taskId,
              sessionId: sessionId,
              message: message,
              resumeToken: resumeToken,
            ),
          );
        case 'evidence':
          _events.add(
            WorkspaceBackendEvent(
              type: WorkspaceBackendEventType.evidence,
              taskId: taskId,
              sessionId: sessionId,
              evidenceId: evidenceId,
              evidenceKind: evidenceKind,
              evidenceTitle: evidenceTitle,
              evidenceText: evidenceText,
              evidenceSource: evidenceSource,
              evidenceStage: evidenceStage,
              evidenceAssetPath: evidenceAssetPath,
              evidenceTimeAgo: evidenceTimeAgo,
            ),
          );
        case 'final':
          if (ok == false || status == 'failed') {
            _events.add(
              WorkspaceBackendEvent(
                type: WorkspaceBackendEventType.error,
                taskId: taskId,
                sessionId: sessionId,
                message: message,
                streamAlreadyDelivered: streamAlreadyDelivered,
                ok: ok,
                status: status,
              ),
            );
            return;
          }
          _events.add(
            WorkspaceBackendEvent(
              type: WorkspaceBackendEventType.finalMessage,
              taskId: taskId,
              sessionId: sessionId,
              message: message,
              streamAlreadyDelivered: streamAlreadyDelivered,
              ok: ok,
              status: status,
            ),
          );
        case 'error':
          _events.add(
            WorkspaceBackendEvent(
              type: WorkspaceBackendEventType.error,
              taskId: taskId,
              sessionId: sessionId,
              message: message,
              streamAlreadyDelivered: streamAlreadyDelivered,
              ok: ok,
              status: status,
            ),
          );
      }
    } catch (error) {
      _events.add(
        WorkspaceBackendEvent(
          type: WorkspaceBackendEventType.error,
          message: 'Failed to parse backend message: $error',
        ),
      );
    }
  }

  bool _isErrorMessage(String? message) {
    if (message == null) {
      return false;
    }
    return message.startsWith('Backend error:') ||
        message.startsWith('OpenClaw call failed:') ||
        message == 'OpenClaw request timed out.';
  }

  void _setOffline(String message) {
    _connected = false;
    _statusMessage = message;
    notifyListeners();
  }
}
