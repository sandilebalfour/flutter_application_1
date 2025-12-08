import 'dart:convert';
import 'package:http/http.dart' as http;

/// Wrapper for calling Groq's LLaMA API (or compatible OpenAI-style endpoints).
///
/// Groq endpoint: https://api.groq.com/openai/v1/chat/completions
/// API Key: available from https://console.groq.com/keys
///
/// This class sends messages in OpenAI format and parses the response accordingly.
class LlamaService {
  /// `baseUrl` should be the full endpoint URL, e.g.
  /// - `https://api.groq.com/openai/v1/chat/completions`
  /// - `https://api.groq.com/openai/v1/responses`
  final String baseUrl;
  final String apiKey;
  final String model;

  LlamaService({required this.baseUrl, required this.apiKey, this.model = 'llama-3.3-70b-versatile'});

  Future<String> sendPrompt(String prompt) async {
    final uri = Uri.parse(baseUrl);

    // Build a request body that works for both OpenAI-style chat completions
    // and Groq Responses API. `messages` is used for chat endpoints; `input`
    // is supported by the /responses endpoint as well.
    final body = {
      'model': model,
      // keep both shapes so Groq/OpenAI compatible endpoints accept it
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      
      'max_tokens': 1024,
    };

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        final decoded = jsonDecode(resp.body);

        // 1) OpenAI-style chat completion: choices[0].message.content
        if (decoded is Map && decoded['choices'] is List && decoded['choices'].isNotEmpty) {
          final choice = decoded['choices'][0];
          if (choice is Map && choice['message'] is Map) {
            final content = choice['message']['content'];
            if (content != null) return content.toString();
          } else if (choice is Map && choice['text'] != null) {
            return choice['text'].toString();
          }
        }

        // 2) Groq Responses-style: `output` array (each item may be string or map)
        if (decoded is Map && decoded['output'] is List) {
          final output = decoded['output'] as List;
          final buffer = StringBuffer();
          for (final item in output) {
            if (item is String) {buffer.write(item);
            }
            else if (item is Map) {
              // common keys: 'content' (string), or 'content' may be a map
              if (item['content'] is String) {
                buffer.write(item['content']);
              } else if (item['content'] is Map) {
                final c = item['content'];
                if (c['text'] is String) {
                  buffer.write(c['text']);
                }
              } else if (item['text'] is String) {
                buffer.write(item['text']);
              }
            }
          }
          final out = buffer.toString();
          if (out.isNotEmpty) return out;
        }

        // 3) Fallback: if top-level `result` or `response` contains text
        if (decoded is Map && decoded['result'] is String) {
          return decoded['result'];
        }
        if (decoded is Map && decoded['response'] is String) {
          return decoded['response'];
        }

        // 4) Give the caller the whole body as a fallback
        return resp.body;
      } catch (e) {
        return resp.body;
      }
    }

    throw Exception('Groq API error ${resp.statusCode}: ${resp.body}');
  }
}
