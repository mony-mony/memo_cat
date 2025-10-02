import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

//ㄷㄹ니ㅓㅣㄴ더리날



/// =======================
///  플랫폼 채널: 정확알람 / 타임존
/// =======================
class ExactAlarmHelper {
  static const _ch = MethodChannel('memo.cat/exact_alarm');

  static Future<bool> canScheduleExact() async {
    try {
      return await _ch.invokeMethod<bool>('canScheduleExactAlarms') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openExactAlarmSettings');
    } catch (_) {}
  }
}

class DeviceTimezone {
  static const _ch = MethodChannel('memo.cat/timezone');

  static Future<String> getLocalTimezoneId() async {
    try {
      final id = await _ch.invokeMethod<String>('getLocalTimezone');
      return id ?? 'UTC';
    } catch (_) {
      return 'UTC';
    }
  }
}

/// =======================
///  알림 서비스 (트레이 전용, 무음)
/// =======================
class NotiService {
  NotiService._();
  static final NotiService _i = NotiService._();
  factory NotiService() => _i;

  final FlutterLocalNotificationsPlugin _flnp =
  FlutterLocalNotificationsPlugin();

  // ✅ 트레이 전용 무음 채널 (서비스 알림과 동일한 성격)
  static const _channelId = 'memo_cat_tray_silent_v1';
  static const _channelName = '메모냥이 무음 리마인더';
  static const _channelDesc = '메모 알림(1시간/30분/정각) — 무음/트레이 전용';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // 타임존
    tz.initializeTimeZones();

    // 알림 권한/초기화
    await _flnp
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: false, // ✅ 무음
      requestBadgePermission: true,
    );

    await _flnp.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (_) {},
    );

    // ✅ 무음/LOW 채널 생성 (헤드업/사운드/진동 X)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.low, // ✅ LOW
      playSound: false, // ✅ 무음
      enableVibration: false,
      showBadge: true,
    );

    await _flnp
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _initialized = true;
  }

  // 백그라운드 탭 핸들러 (top-level이어야 함)
  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse resp) {}

  // === 내부 유틸 ===
  int _noteBaseId(String noteId) => noteId.hashCode & 0x7fffffff;

  (int h1Id, int m30Id, int exactId) _idsFor(String noteId) {
    final base = _noteBaseId(noteId) % 2000000000;
    return (base, (base + 1) % 2000000000, (base + 2) % 2000000000);
  }

  String _fmtFull(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // 제목에 넣을 “남은 시간” 문구
  String _titleForRemaining(Duration diff) {
    if (diff.inMinutes <= 0) return '지금!';
    if (diff.inMinutes == 30) return '30분 남음';
    if (diff.inMinutes == 60) return '1시간 남음';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0 && m > 0) return '${h}시간 ${m}분 남음';
    if (h > 0) return '${h}시간 남음';
    return '${diff.inMinutes}분 남음';
  }

  // ✅ 트레이 전용 무음 NotificationDetails
  NotificationDetails _details({
    required String bigText,
    required String? subText,
    required String groupKey,
  }) {
    final android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low, // ✅ LOW
      priority: Priority.low, // ✅ LOW
      playSound: false, // ✅ 무음
      enableVibration: false,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
      ticker: '메모냥이 알림',
      styleInformation: BigTextStyleInformation(bigText),
      subText: subText,
      groupKey: groupKey,
      setAsGroupSummary: false,
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false, // ✅ 무음
    );

    return NotificationDetails(android: android, iOS: ios);
  }

  /// 1시간 전 / 30분 전 / 정각 예약 (트레이 전용 무음)
  Future<void> scheduleThreeReminders({
    required String noteId,
    required String body, // 메모 텍스트
    required DateTime when, // 사용자가 지정한 시각(로컬)
  }) async {
    await init();

    final (h1Id, m30Id, exactId) = _idsFor(noteId);
    final target = tz.TZDateTime.from(when, tz.local);
    final oneHour = target.subtract(const Duration(hours: 1));
    final halfHour = target.subtract(const Duration(minutes: 30));

    final groupKey = 'memo_cat_$noteId';
    final targetLabel = _fmtFull(target.toLocal());

    Future<void> _zoned(
        int id,
        tz.TZDateTime t,
        Duration remaining,
        ) async {
      if (!t.isAfter(tz.TZDateTime.now(tz.local))) return; // 과거는 스킵

      final title = _titleForRemaining(remaining);
      final details = _details(
        bigText: body,
        subText: '약속 · $targetLabel',
        groupKey: groupKey,
      );

      await _flnp.zonedSchedule(
        id,
        title, // 제목: 1시간 남음/30분 남음/지금!
        body, // 본문: 메모 내용
        t,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: noteId,
      );
    }

    await _zoned(h1Id, oneHour, const Duration(hours: 1)); // 1시간 전
    await _zoned(m30Id, halfHour, const Duration(minutes: 30)); // 30분 전
    await _zoned(exactId, target, Duration.zero); // 정각
  }

  Future<void> cancelReminders(String noteId) async {
    await init();
    final (h1Id, m30Id, exactId) = _idsFor(noteId);
    await _flnp.cancel(h1Id);
    await _flnp.cancel(m30Id);
    await _flnp.cancel(exactId);
  }
}

/// =======================
///  효과음
/// =======================
class Sfx {
  Sfx._();
  static final Sfx _i = Sfx._();
  factory Sfx() => _i;

  AudioContext _alarmCtx = AudioContext(
    android: AudioContextAndroid(
      usageType: AndroidUsageType.alarm,
      contentType: AndroidContentType.sonification,
    ),
  );

  final AudioPlayer _meow = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  final AudioPlayer _swish = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  bool _preloaded = false;

  Future<void> preload() async {
    if (_preloaded) return;
    try {
      await _meow.setAudioContext(_alarmCtx);
      await _swish.setAudioContext(_alarmCtx);
      await _meow.setSource(AssetSource('sounds/meow.mp3'));
      await _swish.setSource(AssetSource('sounds/swish.mp3'));
      _preloaded = true;
    } catch (_) {}
  }

  Future<void> playMeow() async {
    try {
      await _meow.setVolume(0.9);
      await _meow.resume();
    } catch (_) {}
  }

  Future<void> playSwish() async {
    try {
      await _swish.setVolume(0.8);
      await _swish.resume();
    } catch (_) {}
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AudioPlayer.global.setAudioContext(
    AudioContext(
      android: AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
      ),
      iOS: AudioContextIOS(),
    ),
  );

  if (!kReleaseMode) {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['TEST_DEVICE_ID']),
    );
  }
  await MobileAds.instance.initialize();

  runApp(const VoiceNotesApp());
}

class VoiceNotesApp extends StatelessWidget {
  const VoiceNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NotesStore()..load(),
      child: MaterialApp(
        title: '메모냥이',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Pretendard',
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          scaffoldBackgroundColor: const Color(0xFFF4EDF6),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
        ),
        home: const SplashPage(),
      ),
    );
  }
}

class Remind {
  static const _ch = MethodChannel('memo.cat/remind');

  /// whenTs: 목표 시각(밀리초 epoch), noteId: 고유키(같은 약속에 대해 동일 문자열)
  static Future<void> scheduleThree({
    required String noteId,
    required String body,
    required int whenTs,
  }) async {
    await _ch.invokeMethod('scheduleThree', {
      'noteId': noteId,
      'body': body,
      'whenTs': whenTs,
    });
  }

  static Future<void> cancelThree(String noteId) async {
    await _ch.invokeMethod('cancelThree', {'noteId': noteId});
  }
}


/// =======================
///  스플래시
/// =======================
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward();
  late final Animation<double> _fade =
  CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();

    // 스플래시가 뜬 다음 프레임에서 초기화(대기하지 않음)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 초기화 중 시스템 권한 다이얼로그가 떠도 UI는 멈추지 않음
      unawaited(NotiService().init());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(
          const AssetImage('assets/logo/cat_silhouette.png'), context);
    });

    Sfx().preload();

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, __, ___) => const NotesHomePage(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo/cat_silhouette.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 18),
              Text(
                '메모냥이',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: Colors.black.withOpacity(.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================
///  모델/스토어
/// =======================
class Note {
  final String id;
  String content;
  DateTime updatedAt;
  DateTime? remindAt;

  Note({
    required this.id,
    required this.content,
    required this.updatedAt,
    this.remindAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'updatedAt': updatedAt.toIso8601String(),
    'remindAt': remindAt?.toIso8601String(),
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    content: json['content'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    remindAt: (json['remindAt'] as String?) != null
        ? DateTime.parse(json['remindAt'] as String)
        : null,
  );
}

class NotesStore extends ChangeNotifier {
  static const _prefsKey = 'notes_v2_ordered';
  final List<Note> _notes = [];
  List<Note> get notes => List.unmodifiable(_notes);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = (json.decode(raw) as List)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList();
      _notes
        ..clear()
        ..addAll(list);
      notifyListeners();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _notes.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsKey, json.encode(list));
  }

  void add(String content) {
    if (content.trim().isEmpty) return;
    _notes.add(
      Note(
        id: UniqueKey().toString(),
        content: content.trim(),
        updatedAt: DateTime.now(),
      ),
    );
    save();
    notifyListeners();
  }

  void update(String id, String content, {DateTime? remindAt}) {
    final idx = _notes.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    _notes[idx]
      ..content = content
      ..updatedAt = DateTime.now()
      ..remindAt = remindAt;
    save();
    notifyListeners();
  }

  void remove(String id) {
    _notes.removeWhere((e) => e.id == id);
    save();
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _notes.removeAt(oldIndex);
    _notes.insert(newIndex, item);
    save();
    notifyListeners();
  }
}

/// =======================
///  홈 UI
/// =======================
class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _localeId = 'ko_KR';

  static const String _noSpeechHint = '잘 안 들린다냥...';
  bool _noSpeechHintActive = false;

  DateTime? _sessionStart;
  DateTime? _speechStart;
  Timer? _gateTimer;
  int _restarts = 0;
  static const int _maxRestarts = 3;
  bool _heardInSession = false;

  String _ts() => DateTime.now().toIso8601String();

  void _onSpeechError(dynamic error) {
    debugPrint('[speech][ignored] $error');
  }

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();

    _input.addListener(() {
      if (_noSpeechHintActive && _input.text.isNotEmpty) {
        setState(() => _noSpeechHintActive = false);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _speech.stop();
    _gateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: _onSpeechError,
      onStatus: (s) => debugPrint('${_ts()} Speech status: $s'),
    );
    if (available) {
      final locales = await _speech.locales();
      final ko = locales.firstWhere(
            (l) => l.localeId.toLowerCase().startsWith('ko'),
        orElse: () => locales.first,
      );
      setState(() => _localeId = ko.localeId);
    }
  }

  Future<void> _toggleListen() async {
    if (_isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
      final now = DateTime.now();
      final totalSec = _sessionStart == null
          ? 0
          : (now.difference(_sessionStart!).inMilliseconds / 1000.0);
      final speechSec = _speechStart == null
          ? 0
          : (now.difference(_speechStart!).inMilliseconds / 1000.0);
      debugPrint(
          '${_ts()} Manual stop. total=${totalSec.toStringAsFixed(2)}s, speech=${speechSec.toStringAsFixed(2)}s');
      setState(() => _isListening = false);
      _sessionStart = null;
      _speechStart = null;
      _gateTimer?.cancel();
      _gateTimer = null;
      return;
    }

    final ok = await _speech.initialize(
      onError: _onSpeechError,
      onStatus: _handleStatus,
    );
    if (!ok || !await _speech.hasPermission) {
      debugPrint('[speech] permission not granted or init failed');
      return;
    }

    setState(() {
      _isListening = true;
      _noSpeechHintActive = false;
    });

    _restarts = 0;
    _heardInSession = false;
    _sessionStart = DateTime.now();
    _speechStart = null;
    debugPrint('${_ts()} Mic session started');

    _gateTimer?.cancel();
    _gateTimer = Timer(const Duration(seconds: 4), () => _endWithNoSpeechHint());

    await _startListening();
  }

  Future<void> _startListening() async {
    await _speech.listen(
      localeId: _localeId,
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(minutes: 1),
      cancelOnError: true,
      onSoundLevelChange: (double level) {
        if (!_heardInSession && level > 18) {
          _heardInSession = true;
          _speechStart ??= DateTime.now();
          if (_gateTimer?.isActive ?? false) _gateTimer?.cancel();
          debugPrint('${_ts()} Speech detected by level≈${level.toStringAsFixed(1)}');
        }
      },
      onResult: (r) async {
        if (!mounted) return;

        final words = r.recognizedWords.trim();
        if (words.isNotEmpty) {
          _heardInSession = true;
          _speechStart ??= DateTime.now();
          if (_gateTimer?.isActive ?? false) _gateTimer?.cancel();
        }

        if (r.finalResult) {
          try {
            await _speech.stop();
          } catch (_) {}
          final now = DateTime.now();
          final totalSec = _sessionStart == null
              ? 0
              : (now.difference(_sessionStart!).inMilliseconds / 1000.0);
          final speechSec = _speechStart == null
              ? 0
              : (now.difference(_speechStart!).inMilliseconds / 1000.0);
          debugPrint(
              '${_ts()} Final result. total=${totalSec.toStringAsFixed(2)}s, speech=${speechSec.toStringAsFixed(2)}s, text="${words.replaceAll('"', '\\"')}"');

          setState(() {
            _isListening = false;
            if (words.isNotEmpty) {
              _input.text = words;
              _input.selection = TextSelection.fromPosition(
                TextPosition(offset: _input.text.length),
              );
              _noSpeechHintActive = false;
            } else {
              _noSpeechHintActive = true;
            }
          });

          _sessionStart = null;
          _speechStart = null;
          _gateTimer?.cancel();
          _gateTimer = null;
        }
      },
    );
  }

  void _handleStatus(String status) {
    debugPrint('${_ts()} Speech status: $status');
    final withinGate = (_gateTimer?.isActive ?? false);

    if ((status == 'notListening' || status == 'done') &&
        _isListening &&
        !_heardInSession &&
        withinGate &&
        _restarts < _maxRestarts) {
      _restarts += 1;
      debugPrint('${_ts()} Early end → auto-restart #$_restarts');
      _startListening();
    }
  }

  Future<void> _endWithNoSpeechHint() async {
    try {
      await _speech.stop();
    } catch (_) {}
    final now = DateTime.now();
    final totalSec = _sessionStart == null
        ? 0
        : (now.difference(_sessionStart!).inMilliseconds / 1000.0);
    debugPrint('${_ts()} No speech for 4s. End. total=${totalSec.toStringAsFixed(2)}s');
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _noSpeechHintActive = true;
    });
    _sessionStart = null;
    _speechStart = null;
    _gateTimer?.cancel();
    _gateTimer = null;
  }

  void _save() {
    FocusScope.of(context).unfocus();

    final text = _input.text.trim();
    if (text.isEmpty) return;

    context.read<NotesStore>().add(text);
    _input.clear();

    Sfx().playMeow();

    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
      _sessionStart = null;
      _speechStart = null;
      _gateTimer?.cancel();
      _gateTimer = null;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '냥! 완료다냥! 🐾',
          textAlign: TextAlign.center,
        ),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<DateTime?> _pickDateTime({required DateTime initial}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d == null) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        body: Column(
          children: [
            const TopBannerAd(),
            Expanded(
              child: store.notes.isEmpty
                  ? const Center(child: Text('아무것도 없다냥... 🐱'))
                  : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: store.notes.length,
                onReorder: (oldIndex, newIndex) {
                  FocusScope.of(context).unfocus();
                  store.reorder(oldIndex, newIndex);
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final n = store.notes[index];

                  return Dismissible(
                    key: ValueKey(n.id),
                    direction: DismissDirection.horizontal,
                    background: Container(
                      color: Colors.red.withOpacity(.06),
                      alignment: Alignment.centerLeft,
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.red),
                    ),
                    secondaryBackground: Container(
                      color: Colors.red.withOpacity(.06),
                      alignment: Alignment.centerRight,
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.red),
                    ),
                    confirmDismiss: (direction) async {
                      FocusScope.of(context).unfocus();

                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('삭제 할거냥?'),
                          content: const Text('삭제하면 되돌릴 수 없다냥.'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('취소'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                Theme.of(context)
                                    .colorScheme
                                    .error,
                              ),
                              onPressed: () {
                                Sfx().playSwish();
                                Navigator.pop(context, true);
                              },
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                      ) ??
                          false;
                      if (yes) {
                        await NotiService().cancelReminders(n.id);
                      }
                      return yes;
                    },
                    onDismissed: (_) => store.remove(n.id),
                    child: Column(
                      children: [
                        ReorderableDelayedDragStartListener(
                          index: index,
                          child: GestureDetector(
                            onTap: () async {
                              FocusScope.of(context).unfocus();

                              final controller =
                              TextEditingController(text: n.content);
                              DateTime? picked = n.remindAt;

                              final edited = await showDialog<
                                  ({String? text, DateTime? remindAt})>(
                                context: context,
                                builder: (_) => StatefulBuilder(
                                  builder: (ctx, setStateDialog) {
                                    return AlertDialog(
                                      title: const Text('메모 편집'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextField(
                                            controller: controller,
                                            maxLines: null,
                                            textAlign: TextAlign.center,
                                            decoration:
                                            const InputDecoration(
                                                hintText: '내용'),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment:
                                            MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.alarm,
                                                size: 18,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  picked == null
                                                      ? '알림 없음'
                                                      : _fmtFull(picked!),
                                                  textAlign:
                                                  TextAlign.center,
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: () async {
                                              final now = DateTime.now()
                                                  .add(const Duration(
                                                  minutes: 10));
                                              final dt =
                                              await _pickDateTime(
                                                  initial:
                                                  picked ?? now);
                                              if (dt != null) {
                                                setStateDialog(() {
                                                  picked = dt;
                                                });
                                              }
                                            },
                                            child: const Text('알람 시각 선택'),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx),
                                          child: const Text('취소'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                            ctx,
                                            (
                                            text: controller.text
                                                .trim(),
                                            remindAt: picked
                                            ),
                                          ),
                                          child: const Text('저장'),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );

                              if (edited != null &&
                                  (edited.text?.isNotEmpty ?? false)) {
                                context.read<NotesStore>().update(
                                  n.id,
                                  edited.text!,
                                  remindAt: edited.remindAt,
                                );

                                if (edited.remindAt != null) {
                                  await NotiService()
                                      .scheduleThreeReminders(
                                    noteId: n.id,
                                    body: edited.text!,
                                    when: edited.remindAt!,
                                  );
                                } else {
                                  await NotiService()
                                      .cancelReminders(n.id);
                                }
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              margin:
                              const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.fromLTRB(
                                  16, 22, 16, 22),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.9),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Align(
                                    alignment: Alignment.center,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0),
                                      child: Text(
                                        n.content,
                                        textAlign: TextAlign.center,
                                        softWrap: true,
                                        maxLines: null,
                                        style:
                                        const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 10,
                                    top: 6,
                                    child: Text(
                                      _fmt(n.updatedAt),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border:
                        Border.all(color: Colors.black.withOpacity(.25)),
                        color: Colors.white,
                      ),
                      child: TextField(
                        controller: _input,
                        focusNode: _inputFocus,
                        maxLines: 3,
                        minLines: 1,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText:
                          _noSpeechHintActive ? _noSpeechHint : '🐱',
                          border: InputBorder.none,
                        ),
                        onTapOutside: (_) =>
                            FocusScope.of(context).unfocus(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: IconButton(
                              onPressed: _toggleListen,
                              iconSize: 30,
                              tooltip:
                              _isListening ? '듣는 중이다냥~' : '음성 입력',
                              icon: Icon(_isListening
                                  ? Icons.mic
                                  : Icons.mic_none),
                              color: _isListening
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: IconButton(
                              onPressed: _save,
                              tooltip: '저장',
                              iconSize: 30,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                              icon: Image.asset(
                                'assets/icons/화살표.png',
                                width: 28,
                                height: 28,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MM-DD
String _fmt(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.month)}-${two(dt.day)}';
}

// YYYY-MM-DD HH:mm
String _fmtFull(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
class MemoReminder {
  static const _remind = MethodChannel('memo.cat/remind');
  static const _exact  = MethodChannel('memo.cat/exact_alarm');

  static Future<bool> canScheduleExact() async {
    try {
      final ok = await _exact.invokeMethod<bool>('canScheduleExactAlarms');
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openExactSettings() async {
    await _exact.invokeMethod('openExactAlarmSettings');
  }

  /// noteId: 각 메모의 고유 ID(문자열). 같은 ID로 예약하면 취소 시 함께 관리 가능.
  /// whenEpochMs: UTC 기준이든 로컬이든 상관없이 "그 시각의 epoch ms"로만 주면 됨.
  static Future<void> scheduleAt({
    required String noteId,
    required String body,
    required int whenEpochMs,
    String title = '예약 알림',
  }) async {
    await _remind.invokeMethod('scheduleAt', {
      'noteId': noteId,
      'body': body,
      'whenEpochMs': whenEpochMs,
      'title': title,
    });
  }

  static Future<void> cancelAllForNote(String noteId) async {
    await _remind.invokeMethod('cancelAllForNote', {'noteId': noteId});
  }
}

/// 상단 배너 광고
class TopBannerAd extends StatefulWidget {
  const TopBannerAd({super.key});
  @override
  State<TopBannerAd> createState() => _TopBannerAdState();
}

class _TopBannerAdState extends State<TopBannerAd> {
  BannerAd? _ad;
  AdSize? _size;
  bool _isLoaded = false;

  static const _realUnitId = 'ca-app-pub-3557532273437213/4526201503';
  static const _testUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdIfNeeded();
  }

  Future<void> _loadAdIfNeeded() async {
    if (_ad != null) return;

    final width = MediaQuery.of(context).size.width.truncate();
    final AnchoredAdaptiveBannerAdSize? size =
    await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);

    if (!mounted || size == null) return;

    final ad = BannerAd(
      size: size,
      adUnitId: kReleaseMode ? _realUnitId : _testUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _isLoaded = true),
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    );

    await ad.load();
    if (!mounted) {
      ad.dispose();
      return;
    }
    setState(() {
      _ad = ad;
      _size = size;
    });
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _ad == null || _size == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom:
            BorderSide(color: Colors.black.withOpacity(0.06), width: 1),
          ),
        ),
        child: SizedBox(
          width: _size!.width.toDouble(),
          height: _size!.height.toDouble(),
          child: AdWidget(ad: _ad!),
        ),
      ),
    );
  }
}
