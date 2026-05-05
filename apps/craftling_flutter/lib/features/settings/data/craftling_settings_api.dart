import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/craftling_gateway_url.dart';

class CraftlingLlmSettings {
  const CraftlingLlmSettings({
    required this.connected,
    required this.provider,
    required this.profileLabel,
  });

  final bool connected;
  final String provider;
  final String profileLabel;

  factory CraftlingLlmSettings.fromJson(Map<String, dynamic> json) {
    final List<dynamic> profiles = json['profiles'] is List<dynamic>
        ? json['profiles'] as List<dynamic>
        : const <dynamic>[];
    String profileLabel = '';
    if (profiles.isNotEmpty && profiles.first is Map<String, dynamic>) {
      final Map<String, dynamic> profile =
          profiles.first as Map<String, dynamic>;
      profileLabel =
          (profile['email'] as String?) ??
          (profile['displayName'] as String?) ??
          (profile['profileId'] as String?) ??
          '';
    }
    return CraftlingLlmSettings(
      connected: json['connected'] == true,
      provider: (json['provider'] as String?) ?? 'openai-codex',
      profileLabel: profileLabel,
    );
  }
}

class CraftlingUnrealSettings {
  const CraftlingUnrealSettings({
    required this.configured,
    required this.engineRoot,
    required this.projectFile,
    required this.baseUrl,
    required this.defaultBuildTarget,
  });

  final bool configured;
  final String engineRoot;
  final String projectFile;
  final String baseUrl;
  final String defaultBuildTarget;

  factory CraftlingUnrealSettings.fromJson(Map<String, dynamic> json) {
    return CraftlingUnrealSettings(
      configured: json['configured'] == true,
      engineRoot: (json['engineRoot'] as String?) ?? '',
      projectFile: (json['projectFile'] as String?) ?? '',
      baseUrl: (json['baseUrl'] as String?) ?? 'http://127.0.0.1:8080',
      defaultBuildTarget: (json['defaultBuildTarget'] as String?) ?? '',
    );
  }
}

class CraftlingSettingsSnapshot {
  const CraftlingSettingsSnapshot({required this.llm, required this.unreal});

  final CraftlingLlmSettings llm;
  final CraftlingUnrealSettings unreal;

  factory CraftlingSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    return CraftlingSettingsSnapshot(
      llm: CraftlingLlmSettings.fromJson(
        (json['llm'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      unreal: CraftlingUnrealSettings.fromJson(
        (json['unreal'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
    );
  }
}

class CraftlingSettingsApi {
  const CraftlingSettingsApi({required this.gatewayBaseUrl});

  final String gatewayBaseUrl;

  Future<CraftlingSettingsSnapshot> loadSettings() async {
    final Map<String, dynamic> json = await _getJson('/settings');
    return CraftlingSettingsSnapshot.fromJson(json);
  }

  Future<CraftlingCodexOAuthStatus> startCodexOAuth() async {
    final Map<String, dynamic> json = await _postJson('/auth/codex/start');
    if (json['ok'] != true) {
      throw CraftlingSettingsApiException(
        (json['message'] as String?) ??
            (json['error'] as String?) ??
            'Codex OAuth failed to start.',
      );
    }
    return CraftlingCodexOAuthStatus.fromJson(json);
  }

  Future<CraftlingCodexOAuthStatus> loadCodexOAuthStatus() async {
    final Map<String, dynamic> json = await _getJson('/auth/codex/status');
    if (json['ok'] != true) {
      throw CraftlingSettingsApiException(
        (json['message'] as String?) ??
            (json['error'] as String?) ??
            'Codex OAuth failed.',
      );
    }
    return CraftlingCodexOAuthStatus.fromJson(json);
  }

  Future<CraftlingUnrealSettings> saveUnreal({
    required String engineRoot,
    required String projectFile,
    required String baseUrl,
  }) async {
    final Map<String, dynamic> json = await _postJson(
      '/settings/unreal',
      body: <String, String>{
        'engineRoot': engineRoot,
        'projectFile': projectFile,
        'baseUrl': baseUrl,
      },
    );
    if (json['ok'] != true) {
      final List<dynamic> errors = json['errors'] is List<dynamic>
          ? json['errors'] as List<dynamic>
          : const <dynamic>[];
      throw CraftlingSettingsApiException(
        errors.isNotEmpty
            ? errors.map((dynamic item) => item.toString()).join('\n')
            : ((json['message'] as String?) ??
                  (json['error'] as String?) ??
                  'Unreal settings failed validation.'),
      );
    }
    return CraftlingUnrealSettings.fromJson(
      (json['unreal'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final Uri uri = _apiUri(path);
    final http.Response response = await http.get(uri);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, String>? body,
  }) async {
    final Uri uri = _apiUri(path);
    final http.Response response = await http.post(
      uri,
      headers: const <String, String>{'content-type': 'application/json'},
      body: json.encode(body ?? const <String, String>{}),
    );
    return _decodeResponse(response);
  }

  Uri _apiUri(String path) {
    final Uri? uri = toCraftlingGatewayApiUri(gatewayBaseUrl, path);
    if (uri == null) {
      throw const CraftlingSettingsApiException('Invalid Gateway URL.');
    }
    return uri;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final Object? decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const CraftlingSettingsApiException('Invalid Gateway response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CraftlingSettingsApiException(
        (decoded['message'] as String?) ??
            (decoded['error'] as String?) ??
            'Gateway request failed.',
      );
    }
    return decoded;
  }
}

class CraftlingCodexOAuthStatus {
  const CraftlingCodexOAuthStatus({
    required this.running,
    required this.status,
    required this.authUrl,
    required this.browserOpened,
    required this.profileLabel,
    required this.error,
  });

  final bool running;
  final String status;
  final String authUrl;
  final bool? browserOpened;
  final String profileLabel;
  final String error;

  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed';

  factory CraftlingCodexOAuthStatus.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profile =
        (json['profile'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return CraftlingCodexOAuthStatus(
      running: json['running'] == true,
      status: (json['status'] as String?) ?? 'idle',
      authUrl: (json['authUrl'] as String?) ?? '',
      browserOpened: json['browserOpened'] as bool?,
      profileLabel:
          (profile['email'] as String?) ??
          (profile['displayName'] as String?) ??
          (profile['profileId'] as String?) ??
          '',
      error: (json['error'] as String?) ?? '',
    );
  }
}

class CraftlingSettingsApiException implements Exception {
  const CraftlingSettingsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
