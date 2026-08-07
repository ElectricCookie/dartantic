import 'package:dartantic_ai/src/chat_models/openai_chat/openai_audio_format.dart';
import 'package:test/test.dart';

void main() {
  tearDown(OpenAiAudioFormatOverrides.clear);

  group('openAiAudioFormatForMime', () {
    test('maps common mime types', () {
      expect(openAiAudioFormatForMime('audio/wav'), 'wav');
      expect(openAiAudioFormatForMime('audio/mpeg'), 'mp3');
      expect(openAiAudioFormatForMime('audio/mp4'), 'm4a');
      expect(openAiAudioFormatForMime('audio/aac'), 'm4a');
      expect(openAiAudioFormatForMime('audio/ogg'), 'ogg');
      expect(openAiAudioFormatForMime('audio/flac'), 'flac');
    });
  });

  group('OpenAiAudioFormatOverrides', () {
    test('rewrites non-typed formats in request body', () {
      const data = 'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkw';
      OpenAiAudioFormatOverrides.register(data, 'm4a');

      final body = <String, dynamic>{
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_audio',
                'input_audio': {
                  'data': data,
                  'format': 'mp3',
                },
              },
            ],
          },
        ],
      };

      OpenAiAudioFormatOverrides.applyToRequestBody(body);

      final part = (body['messages'] as List).first as Map;
      final content = (part['content'] as List).first as Map;
      final inputAudio = content['input_audio'] as Map;
      expect(inputAudio['format'], 'm4a');
    });
  });
}
