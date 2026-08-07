import 'dart:convert';

import 'package:http/http.dart' as http;

/// Maps MIME types to OpenRouter/OpenAI `input_audio.format` strings.
String openAiAudioFormatForMime(String mimeType) {
  final mime = mimeType.toLowerCase().trim();
  if (mime.contains('wav') || mime == 'audio/wave' || mime == 'audio/x-wav') {
    return 'wav';
  }
  if (mime.contains('mpeg') || mime.endsWith('/mp3') || mime == 'audio/mp3') {
    return 'mp3';
  }
  if (mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')) {
    return 'm4a';
  }
  if (mime.contains('ogg') || mime.contains('vorbis')) {
    return 'ogg';
  }
  if (mime.contains('flac')) {
    return 'flac';
  }
  if (mime.contains('webm')) {
    return 'webm';
  }
  if (mime.contains('opus')) {
    return 'ogg';
  }
  if (mime.contains('aiff')) {
    return 'aiff';
  }
  return 'wav';
}

/// openai_dart only serializes `wav`/`mp3` for input_audio. OpenRouter accepts
/// additional formats (m4a, flac, …). Overrides are applied on the wire.
class OpenAiAudioFormatOverrides {
  static final Map<String, String> _byDataPrefix = {};

  static const _prefixLength = 64;

  /// Registers a wire format override for [base64Data] (matched by prefix).
  static void register(String base64Data, String format) {
    if (format == 'wav' || format == 'mp3') {
      return;
    }
    final key = base64Data.length <= _prefixLength
        ? base64Data
        : base64Data.substring(0, _prefixLength);
    _byDataPrefix[key] = format;
  }

  /// Clears all pending overrides.
  static void clear() => _byDataPrefix.clear();

  /// Whether there are no pending overrides.
  static bool get isEmpty => _byDataPrefix.isEmpty;

  /// Rewrites `input_audio.format` in a chat-completions request body.
  static void applyToRequestBody(Map<String, dynamic> body) {
    if (_byDataPrefix.isEmpty) {
      return;
    }
    final messages = body['messages'];
    if (messages is! List) {
      return;
    }
    for (final message in messages) {
      if (message is! Map) {
        continue;
      }
      final content = message['content'];
      if (content is! List) {
        continue;
      }
      for (final part in content) {
        if (part is! Map) {
          continue;
        }
        if (part['type'] != 'input_audio') {
          continue;
        }
        final inputAudio = part['input_audio'];
        if (inputAudio is! Map) {
          continue;
        }
        final data = inputAudio['data'];
        if (data is! String || data.isEmpty) {
          continue;
        }
        final key = data.length <= _prefixLength
            ? data
            : data.substring(0, _prefixLength);
        final format = _byDataPrefix[key];
        if (format != null) {
          inputAudio['format'] = format;
        }
      }
    }
  }
}

/// Rewrites chat-completion request bodies so OpenRouter gets the real audio
/// format for input_audio parts.
class OpenAiAudioFormatRewriteClient extends http.BaseClient {
  /// Wraps [inner] and rewrites audio formats on chat-completions POSTs.
  OpenAiAudioFormatRewriteClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request &&
        request.method == 'POST' &&
        request.url.path.contains('/chat/completions') &&
        !OpenAiAudioFormatOverrides.isEmpty) {
      try {
        final decoded = jsonDecode(request.body);
        if (decoded is Map<String, dynamic>) {
          OpenAiAudioFormatOverrides.applyToRequestBody(decoded);
          request.body = jsonEncode(decoded);
        } else if (decoded is Map) {
          final body = Map<String, dynamic>.from(decoded);
          OpenAiAudioFormatOverrides.applyToRequestBody(body);
          request.body = jsonEncode(body);
        }
      } catch (_) {
        // Leave body unchanged if it is not JSON we can rewrite.
      } finally {
        OpenAiAudioFormatOverrides.clear();
      }
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
