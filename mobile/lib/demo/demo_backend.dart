import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider/path_provider.dart';

/// In-app fake of the Lolly backend for DEMO builds (AppConfig.demoMode).
///
/// Answers every REST route the app calls (see the route table in
/// [_route]) with the same JSON shapes the real NestJS API returns, so all
/// app code -- state classes, onboarding state machine, discovery, reveal,
/// chat -- runs unmodified. Nothing leaves the device.
///
/// Demo rules a tester should know:
///  - OTP is always `000000`.
///  - **Sign up** (any phone/email) starts a fresh account -> full
///    onboarding. **Log in** with a different identifier lands in a
///    ready-made, fully onboarded account (skip straight to Discovery).
///  - Voice intro "processing" takes a few seconds, then yields 3 drafts.
///  - Discovery has 3 voices; the 1st and 2nd match, the 3rd doesn't.
///  - Chats reply a couple of seconds after you send something.
///
/// Media: voice clips and photos are bundled under assets/demo/ and
/// returned as `asset:` URLs (see shared/widgets/media_sources.dart);
/// voice notes you record are kept as local files (`file:` URLs).
class DemoBackend {
  DemoBackend._();

  static final DemoBackend instance = DemoBackend._();

  static const otp = '000000';
  static const _userId = 'demo-user';
  static const _stateKey = 'lolly.demo_state';

  late final http.Client httpClient = MockClient(_handle);

  final _storage = const FlutterSecureStorage();
  final _rng = Random();

  // ── Persisted account (survives app restarts) ──────────────────────────
  String _status = 'ACCOUNT_CREATED';
  String? _identifier;
  String? _channel;
  bool _loaded = false;

  // ── Session-only state ─────────────────────────────────────────────────
  final Map<String, ({String identifier, String channel, bool signup})> _challenges = {};
  _VoiceAnswer? _voiceAnswer;
  final List<_QueueEntry> _queue = [];
  final Map<String, _Person> _connections = {};
  final Set<String> _chatOpen = {};
  final Map<String, List<Map<String, dynamic>>> _messages = {};
  final Map<String, String> _uploadedFiles = {}; // upload key -> local path
  final List<DemoChatListener> _chatListeners = [];
  int _replyCursor = 0;
  bool _chatsSeeded = false;

  // ── People ─────────────────────────────────────────────────────────────
  static final _people = <String, _Person>{
    'aanya': const _Person('u-aanya', 'Aanya', 'aanya'),
    'meera': const _Person('u-meera', 'Meera', 'meera'),
    'kabir': const _Person('u-kabir', 'Kabir', 'kabir'),
    'rohan': const _Person('u-rohan', 'Rohan', 'rohan'),
  };

  static String _audio(String name) => 'asset:assets/demo/audio/$name.wav';
  static String _photo(String slug) => 'asset:assets/demo/images/photo_$slug.jpg';

  // ── Chat listeners (stand-in for the Socket.IO chat channel) ───────────

  void addChatListener(DemoChatListener l) => _chatListeners.add(l);
  void removeChatListener(DemoChatListener l) => _chatListeners.remove(l);

  // ── Request handling ───────────────────────────────────────────────────

  Future<http.Response> _handle(http.Request request) async {
    await _ensureLoaded();
    // Small, varied latency so loading states are visible like in reality.
    await Future<void>.delayed(Duration(milliseconds: 250 + _rng.nextInt(350)));

    // Signed-URL uploads (voice intro, photo, voice notes).
    if (request.url.scheme == 'demo') return _handleUpload(request);

    var path = request.url.path;
    if (path.startsWith('/v1')) path = path.substring(3);
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
    try {
      final result = await _route(request.method, path, request.url.queryParameters, body);
      return _json(200, result ?? const {});
    } on _DemoError catch (e) {
      return _json(e.status, {'message': e.message});
    }
  }

  http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<Object?> _route(String method, String path, Map<String, String> query, Map<String, dynamic> body) async {
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    String at(int i) => i < seg.length ? seg[i] : '';

    // Auth -------------------------------------------------------------
    if (path == '/auth/signup/start' || path == '/auth/login/start') {
      final id = 'ch-${_rng.nextInt(1 << 30)}';
      _challenges[id] = (
        identifier: (body['identifier'] as String? ?? '').trim(),
        channel: body['channel'] as String? ?? 'PHONE',
        signup: path.contains('signup'),
      );
      return {'challengeId': id};
    }
    if (path == '/auth/signup/verify' || path == '/auth/login/verify') {
      final challenge = _challenges[body['challengeId']];
      if (challenge == null) throw const _DemoError(400, 'That code has expired. Request a new one.');
      if (body['code'] != otp) {
        throw const _DemoError(400, "That code isn't right. In this demo build the code is always 000000.");
      }
      _challenges.remove(body['challengeId']);
      if (challenge.signup) {
        _status = 'ACCOUNT_CREATED';
        _voiceAnswer = null;
      } else if (challenge.identifier != _identifier) {
        // Logging in as someone new: a ready-made, fully onboarded account.
        _status = 'ACTIVE';
      }
      _identifier = challenge.identifier;
      _channel = challenge.channel;
      await _save();
      return {'tokens': _tokens()};
    }
    if (path == '/auth/refresh') return _tokens();
    if (path == '/auth/logout') return const {};
    if (path == '/auth/me') {
      return {
        'id': _userId,
        'email': _channel == 'EMAIL' ? _identifier : null,
        'phone': _channel == 'PHONE' ? _identifier : null,
        'status': _status,
      };
    }

    // Onboarding --------------------------------------------------------
    if (path == '/profile/basic-info') return _advance('BASIC_INFO_DONE');
    if (path == '/profile/preferences') return _advance('PREFERENCES_DONE');
    if (path == '/profile/intent') return _advance('INTENT_DONE');
    if (path == '/profile/photo/upload-url' ||
        path == '/ai-profile/voice/upload-url' ||
        path == '/messaging/voice/upload-url') {
      final key = '${seg.first}/${DateTime.now().microsecondsSinceEpoch}';
      return {'uploadUrl': 'demo://upload/$key', 'key': key};
    }
    if (path == '/profile/photo/complete') return _advance('ACTIVE');
    if (path == '/ai-profile/voice/complete') {
      _voiceAnswer = _VoiceAnswer('va-${_rng.nextInt(1 << 30)}', DateTime.now());
      await _advance('VOICE_RECORDED');
      return _voiceAnswer!.toJson();
    }
    if (path == '/ai-profile/voice/latest') {
      final va = _voiceAnswer ??= _VoiceAnswer('va-resumed', DateTime.now().subtract(const Duration(minutes: 1)));
      return va.toJson();
    }
    if (at(0) == 'ai-profile' && at(1) == 'voice' && seg.length == 3 && method == 'GET') {
      return _requireVoice().toJson();
    }
    if (at(0) == 'ai-profile' && at(1) == 'voice' && at(3) == 'finalize') {
      _requireVoice().approvedByUser = true;
      return _advance('AI_REVIEW_DONE');
    }
    if (at(0) == 'ai-profile' && at(1) == 'claims') {
      final claim = _requireVoice().claims.firstWhere(
            (c) => c.id == at(2),
            orElse: () => throw const _DemoError(404, 'Claim not found'),
          );
      switch (at(3)) {
        case 'edit':
          claim.text = (body['text'] as String? ?? claim.text).trim();
        case 'approve':
          claim.approved = true;
        case 'discard':
          claim.discarded = true;
      }
      return const {};
    }

    // Discovery ---------------------------------------------------------
    if (path == '/discovery/queue/today') {
      _seedQueueIfNeeded();
      return {
        'entries': [
          for (final e in _queue.where((e) => e.decision == null))
            {'id': e.id, 'reasonText': e.reason, 'voiceClipUrl': e.voiceUrl},
        ],
      };
    }
    if (at(0) == 'discovery' && at(3) == 'decide') {
      final entry = _queue.firstWhere((e) => e.id == at(2), orElse: () => throw const _DemoError(404, 'Not found'));
      entry.decision = body['decision'] as String?;
      final matched = entry.decision == 'INTERESTED' && entry.matches;
      if (matched) _connections[entry.connectionId] = entry.person;
      return {'matched': matched, 'connectionId': matched ? entry.connectionId : null};
    }

    // Reveal + Live Snap -----------------------------------------------
    if (at(0) == 'connections' && at(2) == 'reveal') {
      final person = _person(at(1));
      return {'userId': person.userId, 'displayName': person.name, 'photoUrl': _photo(person.slug)};
    }
    if (at(0) == 'connections' && at(2) == 'decline') {
      _connections.remove(at(1));
      return const {};
    }
    if (at(0) == 'live-snap' && at(2) == 'start') {
      _person(at(1));
      return {
        'session': {'id': 'ls-${_rng.nextInt(1 << 30)}'},
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };
    }
    if (at(0) == 'connections' && at(2) == 'snap' && at(3) == 'confirm') {
      final id = at(1);
      final person = _person(id);
      _chatOpen.add(id);
      _messages.putIfAbsent(id, () => [_msg(id, person.userId, text: 'Hey! So glad we matched \u{1F60A} Loved your voice intro.', ago: const Duration(seconds: 5))]);
      return {'matched': true};
    }
    if (path == '/connections/block') {
      final blocked = body['blockedUserId'];
      _chatOpen.removeWhere((id) => _connections[id]?.userId == blocked);
      _connections.removeWhere((_, p) => p.userId == blocked);
      return const {};
    }

    // Messaging ---------------------------------------------------------
    if (path == '/messaging/conversations') {
      _seedChatsIfNeeded();
      final rows = <Map<String, dynamic>>[];
      for (final id in _chatOpen) {
        final p = _connections[id];
        if (p == null) continue;
        final last = (_messages[id] ?? const []).lastOrNull;
        rows.add({
          'connectionId': id,
          'otherUserId': p.userId,
          'displayName': p.name,
          'photoUrl': _photo(p.slug),
          'lastMessage': last == null
              ? null
              : {'type': last['type'], 'textContent': last['textContent'], 'sentAt': last['sentAt']},
        });
      }
      rows.sort((a, b) => _sentAt(b).compareTo(_sentAt(a)));
      return {'conversations': rows};
    }
    if (at(0) == 'messaging' && at(2) == 'messages' && method == 'GET') {
      _seedChatsIfNeeded();
      var list = List<Map<String, dynamic>>.of(_messages[at(1)] ?? const []);
      final since = query['since'];
      final before = query['before'];
      if (since != null) list = list.where((m) => DateTime.parse(m['sentAt'] as String).isAfter(DateTime.parse(since))).toList();
      if (before != null) list = list.where((m) => DateTime.parse(m['sentAt'] as String).isBefore(DateTime.parse(before))).toList();
      return {'messages': list, 'hasMore': false};
    }
    if (at(0) == 'messaging' && at(2) == 'messages' && method == 'POST') {
      final id = at(1);
      final person = _person(id);
      final isVoice = body['type'] == 'VOICE';
      final local = isVoice ? _uploadedFiles[body['audioUrl']] : null;
      final message = _msg(
        id,
        _userId,
        text: isVoice ? null : body['textContent'] as String?,
        audioUrl: local != null ? 'file:$local' : null,
        durationSec: isVoice ? body['audioDurationSec'] as int? : null,
      );
      _messages.putIfAbsent(id, () => []).add(message);
      _scheduleReply(id, person);
      return message;
    }
    if (at(0) == 'messaging' && (at(2) == 'read' || at(2) == 'delivered')) return const {};

    // Safety + notifications ------------------------------------------
    if (path == '/moderation/reports') return {'id': 'rep-${_rng.nextInt(1 << 30)}'};
    if (path.startsWith('/notifications/')) return const {};

    throw _DemoError(404, 'Demo build: no mock for $method $path');
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Map<String, String> _tokens() => {
        'accessToken': 'demo-access-${DateTime.now().millisecondsSinceEpoch}',
        'refreshToken': 'demo-refresh-${DateTime.now().millisecondsSinceEpoch}',
      };

  Future<Map<String, dynamic>> _advance(String status) async {
    _status = status;
    await _save();
    return const {};
  }

  _VoiceAnswer _requireVoice() => _voiceAnswer ?? (throw const _DemoError(404, 'No voice answer yet'));

  _Person _person(String connectionId) {
    _seedChatsIfNeeded();
    return _connections[connectionId] ?? (throw const _DemoError(404, 'Connection not found'));
  }

  DateTime _sentAt(Map<String, dynamic> conversation) {
    final last = conversation['lastMessage'] as Map<String, dynamic>?;
    return last == null ? DateTime(2000) : DateTime.parse(last['sentAt'] as String);
  }

  Map<String, dynamic> _msg(
    String connectionId,
    String senderId, {
    String? text,
    String? audioUrl,
    int? durationSec,
    Duration ago = Duration.zero,
    bool read = true,
  }) {
    final sent = DateTime.now().toUtc().subtract(ago);
    return {
      'id': 'm-${sent.microsecondsSinceEpoch}-${_rng.nextInt(1 << 20)}',
      'connectionId': connectionId,
      'senderId': senderId,
      'type': audioUrl != null || durationSec != null ? 'VOICE' : 'TEXT',
      'textContent': text,
      'audioUrl': audioUrl,
      'audioDurationSec': durationSec,
      'sentAt': sent.toIso8601String(),
      'deliveredAt': sent.toIso8601String(),
      'readAt': read ? sent.toIso8601String() : null,
    };
  }

  void _seedQueueIfNeeded() {
    if (_queue.isNotEmpty) return;
    _queue.addAll([
      _QueueEntry(
        'q-1',
        "You both light up talking about long drives and tiny cafés -- and you're both secret bakers.",
        _audio('voice_aanya'),
        _people['aanya']!,
        'c-aanya',
        matches: true,
      ),
      _QueueEntry(
        'q-2',
        'You both said you want spontaneous road trips and someone who makes you laugh.',
        _audio('voice_meera'),
        _people['meera']!,
        'c-meera',
        matches: true,
      ),
      _QueueEntry(
        'q-3',
        'You both mentioned trekking in the hills and a soft spot for board games.',
        _audio('voice_kabir'),
        _people['kabir']!,
        'c-kabir',
        matches: false,
      ),
    ]);
  }

  /// One conversation already in progress, so Chat isn't empty on first
  /// open (includes a voice note from them).
  void _seedChatsIfNeeded() {
    // A flag, not "is c-rohan present?": blocking Rohan removes him, and
    // he must stay gone.
    if (_chatsSeeded) return;
    _chatsSeeded = true;
    final rohan = _people['rohan']!;
    _connections['c-rohan'] = rohan;
    _chatOpen.add('c-rohan');
    _messages['c-rohan'] = [
      _msg('c-rohan', rohan.userId, text: 'That Live Snap was fun \u{1F604}', ago: const Duration(hours: 5)),
      _msg('c-rohan', _userId, text: 'Haha it was! Your dog photobombing was the highlight.', ago: const Duration(hours: 4, minutes: 52)),
      _msg('c-rohan', rohan.userId, audioUrl: _audio('voice_rohan'), durationSec: 12, ago: const Duration(hours: 4, minutes: 40)),
      _msg('c-rohan', rohan.userId, text: 'Brunch on Sunday? I know a place with ridiculous pancakes.', ago: const Duration(minutes: 38), read: false),
    ];
  }

  static const _replies = [
    'Haha, I love that \u{1F602}',
    'Okay you have my attention. Tell me more!',
    'That sounds like a perfect weekend honestly.',
    'Wait, really? Same here!',
    'Coffee this Saturday? I know a spot with amazing cinnamon rolls \u{2615}',
  ];

  /// "They" reply a couple of seconds later, pushed through the chat
  /// listeners exactly like the real socket's `message:new`. Every third
  /// reply is a voice note.
  void _scheduleReply(String connectionId, _Person person) {
    Timer(const Duration(milliseconds: 900), () {
      for (final l in List.of(_chatListeners)) {
        l.onRead?.call({'upTo': DateTime.now().toUtc().toIso8601String()});
      }
    });
    Timer(Duration(milliseconds: 2200 + _rng.nextInt(1200)), () {
      final n = _replyCursor++;
      final voice = n % 3 == 2;
      final reply = voice
          ? _msg(connectionId, person.userId, audioUrl: _audio('voice_note_reply'), durationSec: 6)
          : _msg(connectionId, person.userId, text: _replies[n % _replies.length]);
      _messages.putIfAbsent(connectionId, () => []).add(reply);
      for (final l in List.of(_chatListeners)) {
        l.onNewMessage?.call(Map<String, dynamic>.of(reply));
      }
    });
  }

  Future<http.Response> _handleUpload(http.Request request) async {
    if (request.method != 'PUT') return _json(405, {'message': 'PUT only'});
    final key = request.url.path.replaceFirst('/', '');
    try {
      final dir = await getTemporaryDirectory();
      final ext = (request.headers['content-type'] ?? '').contains('image') ? 'jpg' : 'm4a';
      final file = File('${dir.path}/demo_${key.replaceAll('/', '_')}.$ext');
      await file.writeAsBytes(request.bodyBytes);
      _uploadedFiles[key] = file.path;
    } catch (_) {
      // Keeping the bytes is only for playback of your own voice notes.
    }
    return http.Response('', 200);
  }

  // ── Persistence ────────────────────────────────────────────────────────

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _stateKey);
      if (raw == null) return;
      final s = jsonDecode(raw) as Map<String, dynamic>;
      _status = s['status'] as String? ?? _status;
      _identifier = s['identifier'] as String?;
      _channel = s['channel'] as String?;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await _storage.write(
        key: _stateKey,
        value: jsonEncode({'status': _status, 'identifier': _identifier, 'channel': _channel}),
      );
    } catch (_) {}
  }
}

/// Receives the demo's "socket" events (see ChatSocketClient in demo mode).
class DemoChatListener {
  DemoChatListener({this.onNewMessage, this.onRead});

  void Function(Map<String, dynamic> payload)? onNewMessage;
  void Function(Map<String, dynamic> payload)? onRead;
}

class _DemoError implements Exception {
  const _DemoError(this.status, this.message);
  final int status;
  final String message;
}

class _Person {
  const _Person(this.userId, this.name, this.slug);
  final String userId;
  final String name;
  final String slug;
}

class _QueueEntry {
  _QueueEntry(this.id, this.reason, this.voiceUrl, this.person, this.connectionId, {required this.matches});
  final String id;
  final String reason;
  final String voiceUrl;
  final _Person person;
  final String connectionId;
  final bool matches;
  String? decision;
}

class _Claim {
  _Claim(this.id, this.text);
  final String id;
  String text;
  bool approved = false;
  bool discarded = false;
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'approved': approved, 'discarded': discarded};
}

/// Voice-intro "processing": UPLOADED -> TRANSCRIBING -> EXTRACTING ->
/// DRAFT_READY over ~5 s of wall-clock time, polled by the app as usual.
class _VoiceAnswer {
  _VoiceAnswer(this.id, this.createdAt);
  final String id;
  final DateTime createdAt;
  bool approvedByUser = false;
  final claims = [
    _Claim('cl-1', 'I spend my weekends exploring new cafés and bookshops around the city.'),
    _Claim('cl-2', "I'm looking for someone kind and curious who's up for spontaneous plans."),
    _Claim('cl-3', 'Friends say I give the best restaurant recommendations.'),
  ];

  String get status {
    if (approvedByUser) return 'USER_APPROVED';
    final s = DateTime.now().difference(createdAt).inMilliseconds;
    if (s < 1500) return 'UPLOADED';
    if (s < 3000) return 'TRANSCRIBING';
    if (s < 4500) return 'EXTRACTING';
    return 'DRAFT_READY';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'failureReason': null,
        'claims': [for (final c in claims) c.toJson()],
      };
}
