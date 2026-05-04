import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/network/craftling_gateway_url.dart';

class ChatController extends ChangeNotifier {
  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<String, int> _pendingAssistantIndexesBySession = <String, int>{};
  final Queue<int> _pendingAssistantIndexes = Queue<int>();
  final Queue<String> _pendingUserEchoes = Queue<String>();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  bool _connected = false;
  int _msgIdCounter = 0;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  bool get connected => _connected;

  @override
  void dispose() {
    _channelSubscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void connect(String input) {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      _addSystemMessage('Gateway URL is required.');
      return;
    }

    final String? wsUrl = toCraftlingGatewayWebSocketUrl(trimmedInput);
    if (wsUrl == null) {
      _addSystemMessage(
        'Gateway URL must start with http://, https://, ws://, or wss://',
      );
      return;
    }

    _channelSubscription?.cancel();
    _channel?.sink.close();

    try {
      final nextChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = nextChannel;
      _connected = true;
      notifyListeners();
      _addSystemMessage('Connected to $wsUrl');

      _channelSubscription = nextChannel.stream.listen(
        _handleSocketData,
        onError: (Object error) {
          _connected = false;
          notifyListeners();
          _addSystemMessage('WebSocket error: $error');
        },
        onDone: () {
          _connected = false;
          notifyListeners();
          _addSystemMessage('Connection closed');
        },
      );
    } catch (error) {
      _connected = false;
      notifyListeners();
      _addSystemMessage('Connection failed: $error');
    }
  }

  void sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !_connected) {
      return;
    }

    final msgId = (_msgIdCounter++).toString();
    _messages.add(
      ChatMessage(role: MessageRole.user, content: trimmed, id: msgId),
    );
    _pendingUserEchoes.add(trimmed);
    _createPendingAssistant();
    notifyListeners();

    try {
      _channel?.sink.add(
        json.encode(<String, String>{
          'type': 'task_message',
          'taskId': 'chat-$msgId',
          'message': trimmed,
        }),
      );
    } catch (error) {
      _failPendingAssistant('Send failed: $error');
    }
  }

  void _handleSocketData(dynamic data) {
    try {
      final jsonData = json.decode(data.toString()) as Map<String, dynamic>;
      final type = jsonData['type'] as String?;
      final message = jsonData['message'] as String?;
      final sessionId = jsonData['sessionId'] as String?;
      final ok = jsonData['ok'] as bool?;
      final status = jsonData['status'] as String?;

      if (type == 'user' && message != null) {
        final wasLocalEcho = _consumePendingUserEcho(message);
        if (!wasLocalEcho) {
          _messages.add(ChatMessage(role: MessageRole.user, content: message));
          notifyListeners();
        }
        return;
      }

      if (type == 'system' && message != null) {
        if (message.startsWith('OpenClaw is thinking...') ||
            message == 'OpenClaw run started.') {
          _ensurePendingAssistant(sessionId: sessionId);
          notifyListeners();
        } else if (message.startsWith('Backend error:') ||
            message.startsWith('OpenClaw call failed:') ||
            message == 'OpenClaw request timed out.') {
          _failPendingAssistant(message, sessionId: sessionId);
        } else {
          _addSystemMessage(message);
        }
        return;
      }

      if (type == 'stream') {
        final delta = jsonData['delta'] as String? ?? '';
        if (delta.isNotEmpty) {
          _appendAssistantStream(delta, sessionId: sessionId);
        }
        return;
      }

      if (type == 'final' && message != null) {
        if (ok == false || status == 'failed') {
          _failPendingAssistant(message, sessionId: sessionId);
          return;
        }
        _resolveAssistantMessage(message, sessionId: sessionId);
        return;
      }

      if (type == 'error') {
        _failPendingAssistant(
          message ?? 'Craftling Gateway error.',
          sessionId: sessionId,
        );
      }
    } catch (error) {
      _addSystemMessage('Failed to parse message: $error');
    }
  }

  void _addSystemMessage(String content) {
    _messages.add(ChatMessage(role: MessageRole.system, content: content));
    notifyListeners();
  }

  bool _consumePendingUserEcho(String message) {
    if (_pendingUserEchoes.isEmpty) {
      return false;
    }

    final Queue<String> remaining = Queue<String>();
    var matched = false;

    while (_pendingUserEchoes.isNotEmpty) {
      final candidate = _pendingUserEchoes.removeFirst();
      if (!matched && candidate == message) {
        matched = true;
        continue;
      }
      remaining.add(candidate);
    }

    _pendingUserEchoes.addAll(remaining);
    return matched;
  }

  int _createPendingAssistant({String? sessionId}) {
    final pendingIndex = _messages.length;
    _messages.add(
      ChatMessage(role: MessageRole.assistant, content: '', isPending: true),
    );
    _pendingAssistantIndexes.add(pendingIndex);
    if (sessionId != null && sessionId.isNotEmpty) {
      _pendingAssistantIndexesBySession[sessionId] = pendingIndex;
    }
    return pendingIndex;
  }

  int _ensurePendingAssistant({String? sessionId}) {
    if (sessionId != null && sessionId.isNotEmpty) {
      final existingIndex = _pendingAssistantIndexesBySession[sessionId];
      if (existingIndex != null) {
        return existingIndex;
      }
      if (_pendingAssistantIndexes.isNotEmpty) {
        final fallbackIndex = _pendingAssistantIndexes.last;
        _pendingAssistantIndexesBySession[sessionId] = fallbackIndex;
        return fallbackIndex;
      }
      return _createPendingAssistant(sessionId: sessionId);
    }

    if (_pendingAssistantIndexes.isNotEmpty) {
      return _pendingAssistantIndexes.last;
    }

    return _createPendingAssistant();
  }

  int? _takePendingAssistant({String? sessionId}) {
    if (sessionId != null && sessionId.isNotEmpty) {
      final index = _pendingAssistantIndexesBySession.remove(sessionId);
      if (index != null) {
        _pendingAssistantIndexes.remove(index);
        return index;
      }
    }

    if (_pendingAssistantIndexes.isNotEmpty) {
      return _pendingAssistantIndexes.removeFirst();
    }

    return null;
  }

  void _appendAssistantStream(String delta, {String? sessionId}) {
    final index = _ensurePendingAssistant(sessionId: sessionId);
    _messages[index].content += delta;
    notifyListeners();
  }

  void _resolveAssistantMessage(String content, {String? sessionId}) {
    final index = _takePendingAssistant(sessionId: sessionId);
    if (index != null) {
      _messages[index]
        ..content = content
        ..isPending = false;
    } else {
      _messages.add(ChatMessage(role: MessageRole.assistant, content: content));
    }
    notifyListeners();
  }

  void _failPendingAssistant(String content, {String? sessionId}) {
    final index = _takePendingAssistant(sessionId: sessionId);
    if (index != null) {
      _messages[index]
        ..content = content
        ..isPending = false;
    } else {
      _messages.add(ChatMessage(role: MessageRole.system, content: content));
    }
    notifyListeners();
  }
}
