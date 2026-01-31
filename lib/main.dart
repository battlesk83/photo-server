import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:seongyu_samchon_counsel/chat_page.dart';
import 'package:seongyu_samchon_counsel/models/counsel.dart';
import 'package:seongyu_samchon_counsel/screens/artist_page.dart';
import 'package:seongyu_samchon_counsel/screens/passport_editor_page.dart';

/// 회차, 당첨 6개 번호, 보너스 번호
class LottoWinningRow {
  const LottoWinningRow({
    required this.round,
    required this.numbers,
    required this.bonus,
  });
  final int round;
  final List<int> numbers;
  final int bonus;
}

const String _lottoWinningListUrl =
    'https://data.soledot.com/lottowinnumber/fo/lottowinnumberlist.sd';

Future<List<LottoWinningRow>> fetchLottoWinningList() async {
  try {
    final res = await http.get(Uri.parse(_lottoWinningListUrl))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final doc = html_parser.parse(res.body);
    final rows = doc.querySelectorAll('table tr');
    final list = <LottoWinningRow>[];
    for (final tr in rows) {
      final tds = tr.querySelectorAll('td');
      if (tds.length < 3) continue;
      final roundText = tds[0].text.trim();
      final round = int.tryParse(roundText.replaceAll(RegExp(r'[^0-9]'), ''));
      if (round == null) continue;
      final numsText = tds[1].text.trim();
      final numbers = RegExp(r'\d+')
          .allMatches(numsText)
          .map((m) => int.tryParse(m.group(0) ?? '') ?? 0)
          .where((n) => n >= 1 && n <= 45)
          .toList();
      if (numbers.length != 6) continue;
      final bonusText = tds[2].text.trim();
      final bonusVal = int.tryParse(RegExp(r'\d+').firstMatch(bonusText)?.group(0) ?? '');
      if (bonusVal == null || bonusVal < 1 || bonusVal > 45) continue;
      list.add(LottoWinningRow(round: round, numbers: numbers, bonus: bonusVal));
    }
    return list;
  } catch (_) {
    return [];
  }
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 썬형의 상담센터',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with RouteAware {
  late final AudioPlayer _audioPlayer;
  bool _bgmStarted = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _playBackgroundMusic();
  }

  Future<void> _playBackgroundMusic() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop); // 반복 재생
      await _audioPlayer.setVolume(0.5); // 볼륨 조절 (0.0 ~ 1.0)
      await _audioPlayer.play(AssetSource('audios/main.mp3'));
      _bgmStarted = true;
    } catch (e) {
      // 음악 파일이 없거나 로드 실패 시 무시
      debugPrint('배경음악 재생 실패: $e');
    }
  }

  Future<void> _stopBackgroundMusic() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {
      // ignore
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // 메인 화면에서 다른 화면으로 갈 때(영상 재생 화면 등) 배경음악 정지
    _stopBackgroundMusic();
  }

  @override
  void didPopNext() {
    // 다른 화면에서 메인 화면으로 돌아왔을 때 배경음악 재생(항상 재시작)
    _playBackgroundMusic();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFF8E7),
              const Color(0xFFFFF0D4),
              const Color(0xFFFFE4B8),
              const Color(0xFFFFD9A0).withOpacity(0.95),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 태양 느낌의 부드러운 원형 그라데이션 (배경)
              Positioned(
                top: -80,
                left: MediaQuery.of(context).size.width * 0.5 - 140,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFE082).withOpacity(0.35),
                        const Color(0xFFFFCC80).withOpacity(0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                right: -60,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFB74D).withOpacity(0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  // ✅ 상단 타이틀 이미지 (좌우 여백 최소, 머리 잘리지 않게 contain)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: Image.asset(
                          'assets/images/title_sun.png',
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
                  // ✅ 천사썬(왼쪽) / 팩폭썬(오른쪽) - 이미지 아래 각각 정렬
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: GestureDetector(
                                  onTap: () {
                                    SystemSound.play(SystemSoundType.click);
                                    _stopBackgroundMusic();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const VideoIntroPage(
                                          title: '천사 썬',
                                          assetPath: 'assets/videos/angel.mp4',
                                          mode: CounselMode.angel,
                                        ),
                                      ),
                                    );
                                  },
                                  child: _FancyButton(
                                    height: 64,
                                    borderRadius: 20,
                                    gradientColors: const [
                                      Color(0xFF8EC5FC),
                                      Color(0xFFE0C3FC),
                                    ],
                                    shadowOpacity: 0.18,
                                    icon: Icons.favorite,
                                    iconColor: Colors.white,
                                    text: '천사썬 상담받기',
                                    textStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    SystemSound.play(SystemSoundType.click);
                                    _stopBackgroundMusic();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const VideoIntroPage(
                                          title: '팩폭 썬',
                                          assetPath: 'assets/videos/fact.mp4',
                                          mode: CounselMode.fact,
                                        ),
                                      ),
                                    );
                                  },
                                  child: _FancyButton(
                                    height: 64,
                                    borderRadius: 20,
                                    gradientColors: const [
                                      Color(0xFF232526),
                                      Color(0xFF414345),
                                    ],
                                    shadowOpacity: 0.35,
                                    icon: Icons.whatshot,
                                    iconColor: Colors.orangeAccent,
                                    text: '팩폭썬 상담받기',
                                    textStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ✅ 나머지 버튼 영역
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: Column(
                      children: [

                  // 🎨 나도 예술가 버튼
                  GestureDetector(
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ArtistPage(),
                        ),
                      );
                    },
                    child: _FancyButton(
                      height: 56,
                      borderRadius: 16,
                      gradientColors: const [
                        Color(0xFF6A1B9A),
                        Color(0xFFAB47BC),
                      ],
                      shadowOpacity: 0.25,
                      icon: Icons.palette,
                      iconColor: Colors.white,
                      text: '🎨 나도 예술가',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 🎱 무료 로또추첨기 버튼 (동영상 재생 후 로또 페이지)
                  GestureDetector(
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VideoIntroPage(
                            title: '무료 로또추첨기',
                            assetPath: 'assets/videos/lotto.mp4',
                            nextPage: LottoPage(),
                            nextButtonLabel: '추첨 바로하기',
                            showLottoNumbers: true,
                          ),
                        ),
                      );
                    },
                    child: _FancyButton(
                      height: 56,
                      borderRadius: 16,
                      gradientColors: const [
                        Color(0xFFE65100),
                        Color(0xFFFF9800),
                      ],
                      shadowOpacity: 0.25,
                      icon: Icons.confirmation_number,
                      iconColor: Colors.white,
                      text: '무료 로또추첨기',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 📷 증명·여권사진 만들기 (밑에서 두번째)
                  GestureDetector(
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PassportEditorPage(),
                        ),
                      );
                    },
                    child: _FancyButton(
                      height: 56,
                      borderRadius: 16,
                      gradientColors: const [
                        Color(0xFF1565C0),
                        Color(0xFF42A5F5),
                      ],
                      shadowOpacity: 0.25,
                      icon: Icons.badge,
                      iconColor: Colors.white,
                      text: '증명·여권사진 만들기 (미완성)',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 🎵 힐링 무료음악 (맨 아래)
                  GestureDetector(
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ComingSoonPage(
                            title: '힐링 무료음악',
                          ),
                        ),
                      );
                    },
                    child: _FancyButton(
                      height: 56,
                      borderRadius: 16,
                      gradientColors: const [
                        Color(0xFF56AB2F),
                        Color(0xFFA8E063),
                      ],
                      shadowOpacity: 0.2,
                      icon: Icons.music_note,
                      iconColor: Colors.white,
                      text: '마음의 안정을 찾는 힐링 무료음악 (준비중)',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }
}

/// 무료 로또추첨기 (1~45 중복 없이 6개, 번호 돌아가다 멈추는 이펙트 + 효과음)
class LottoPage extends StatefulWidget {
  const LottoPage({super.key});

  @override
  State<LottoPage> createState() => _LottoPageState();
}

class _LottoPageState extends State<LottoPage> with TickerProviderStateMixin {
  static const int _min = 1;
  static const int _max = 45;
  static const int _count = 6;

  List<int> _finalNumbers = [];
  List<int> _displayNumbers = List.filled(_count, 0);
  int _stoppedCount = 0;
  bool _isAnimating = false;
  final Random _random = Random();
  late AnimationController _spinController;
  List<List<int>> _savedDraws = [];
  static const String _prefKeyLottoHistory = 'lotto_history';
  static const int _maxSavedDraws = 50;
  List<LottoWinningRow> _winningList = [];
  bool _winningLoading = true;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _loadSavedDraws();
    fetchLottoWinningList().then((list) {
      if (mounted) setState(() {
        _winningList = list;
        _winningLoading = false;
      });
    });
  }

  Future<void> _loadSavedDraws() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyLottoHistory);
      if (json == null) return;
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null) return;
      setState(() {
        _savedDraws = list
            .map((e) => (e as List<dynamic>).map((n) => n as int).toList())
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _saveDraw(List<int> numbers) async {
    try {
      _savedDraws.insert(0, List<int>.from(numbers));
      if (_savedDraws.length > _maxSavedDraws) {
        _savedDraws = _savedDraws.take(_maxSavedDraws).toList();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKeyLottoHistory,
        jsonEncode(_savedDraws.map((e) => e).toList()),
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  List<int> _generateNumbers() {
    final set = <int>{};
    while (set.length < _count) {
      set.add(_min + _random.nextInt(_max - _min + 1));
    }
    return set.toList()..sort();
  }

  Future<void> _startDraw() async {
    if (_isAnimating) return;
    setState(() {
      _finalNumbers = _generateNumbers();
      for (var i = 0; i < _count; i++) {
        _displayNumbers[i] = _min + _random.nextInt(_max - _min + 1);
      }
      _stoppedCount = 0;
      _isAnimating = true;
    });
    _spinController.repeat();

    const cycleMs = 45;
    const totalCycleMs = 1200;
    const pauseBetweenBalls = 180;

    for (var slot = 0; slot < _count; slot++) {
      var elapsed = 0;
      while (elapsed < totalCycleMs && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: cycleMs));
        if (!mounted) return;
        elapsed += cycleMs;
        setState(() {
          _displayNumbers[slot] = _min + _random.nextInt(_max - _min + 1);
        });
      }
      if (!mounted) return;
      setState(() {
        _displayNumbers[slot] = _finalNumbers[slot];
        _stoppedCount = slot + 1;
      });
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
      await Future<void>.delayed(const Duration(milliseconds: pauseBetweenBalls));
    }

    if (mounted) {
      _spinController.stop();
      setState(() => _isAnimating = false);
      await _saveDraw(_finalNumbers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('무료 로또추첨기'),
        backgroundColor: const Color(0xFFE65100),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Text(
                '썬형이 추천해주는 1등 할 확률높은 번호',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF37474F),
                      const Color(0xFF263238),
                      const Color(0xFF1A237E).withOpacity(0.9),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: const Color(0xFFE65100).withOpacity(0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '🎱 로또 추첨기',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.95),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (i) {
                            final idx = i;
                            final isStopped = idx < _stoppedCount;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: _LottoBall(
                                number: _displayNumbers[idx],
                                isStopped: isStopped,
                                index: idx,
                                spinAnimation: _isAnimating ? _spinController : null,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (i) {
                            final idx = 3 + i;
                            final isStopped = idx < _stoppedCount;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: _LottoBall(
                                number: _displayNumbers[idx],
                                isStopped: isStopped,
                                index: idx,
                                spinAnimation: _isAnimating ? _spinController : null,
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!_isAnimating && _finalNumbers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFE65100).withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '추천 번호: ${_finalNumbers.join('  ·  ')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFBF360C),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '추첨 목록',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '최근 회차 1등 당첨번호',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: _winningLoading
                                ? const Center(child: CircularProgressIndicator())
                                : ListView.builder(
                                    padding: const EdgeInsets.only(left: 4, right: 4),
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: _winningList.length > 10 ? 10 : _winningList.length,
                                    itemBuilder: (context, i) {
                                      final row = _winningList[i];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE65100),
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 2,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${row.round}회',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment: Alignment.centerLeft,
                                                  child: Text(
                                                    row.numbers.join(', '),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '생성한 로또번호',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(left: 4, right: 4),
                              physics: const BouncingScrollPhysics(),
                              itemCount: _savedDraws.length,
                              itemBuilder: (context, i) {
                                final nums = _savedDraws[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF455A64),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 2,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${i + 1}회',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              nums.join(', '),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAnimating ? null : _startDraw,
                  icon: Icon(_isAnimating ? Icons.hourglass_empty : Icons.refresh),
                  label: Text(_isAnimating ? '추첨 중...' : '추첨하기'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  SystemSound.play(SystemSoundType.click);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('뒤로가기'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade400),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LottoBall extends StatelessWidget {
  final int number;
  final bool isStopped;
  final int index;
  final Animation<double>? spinAnimation;

  const _LottoBall({
    required this.number,
    required this.isStopped,
    required this.index,
    this.spinAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFFF44336),
      const Color(0xFF2196F3),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
    ];
    final color = colors[index % colors.length];
    final ballContent = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isStopped
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withOpacity(0.85)],
              )
            : null,
        color: isStopped ? null : Colors.grey.shade500,
        boxShadow: [
          BoxShadow(
            color: (isStopped ? color : Colors.grey.shade700).withOpacity(0.55),
            blurRadius: isStopped ? 12 : 6,
            spreadRadius: isStopped ? 3 : 1,
            offset: Offset(0, isStopped ? 4 : 2),
          ),
          if (isStopped)
            BoxShadow(
              color: Colors.white.withOpacity(0.35),
              blurRadius: 4,
              spreadRadius: 0,
              offset: const Offset(-1, -1),
            ),
        ],
      ),
      child: Center(
        child: Text(
          number > 0 ? '$number' : '-',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: isStopped ? Colors.white : Colors.grey.shade200,
            shadows: isStopped
                ? [
                    Shadow(
                      color: Colors.black.withOpacity(0.35),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );

    final scale = isStopped ? 1.08 : 1.0;
    final scaledContent = Transform.scale(
      scale: scale,
      child: ballContent,
    );

    if (spinAnimation != null && !isStopped) {
      return AnimatedBuilder(
        animation: spinAnimation!,
        builder: (context, child) {
          return Transform.rotate(
            angle: spinAnimation!.value * 2 * 3.14159265,
            child: child,
          );
        },
        child: scaledContent,
      );
    }
    return scaledContent;
  }
}

/// 서비스 예정 화면 (메시지 + 뒤로가기)
class ComingSoonPage extends StatelessWidget {
  final String title;

  const ComingSoonPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.grey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.construction, size: 64, color: Colors.orange.shade700),
              const SizedBox(height: 24),
              const Text(
                '서비스 예정입니다',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    SystemSound.play(SystemSoundType.click);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('뒤로가기'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.grey.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 버튼 디자인 위젯 (고급 그라데이션 + 그림자)
class _FancyButton extends StatelessWidget {
  final double height;
  final double borderRadius;
  final List<Color> gradientColors;
  final double shadowOpacity;
  final IconData icon;
  final Color iconColor;
  final String text;
  final TextStyle textStyle;

  const _FancyButton({
    required this.height,
    required this.borderRadius,
    required this.gradientColors,
    required this.shadowOpacity,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(shadowOpacity),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Text(text, style: textStyle),
        ],
      ),
    );
  }
}

/// ✅ 영상 재생 페이지 (자동재생 / 전체화면 느낌)
/// mode가 있으면 "채팅 시작" → ChatPage, nextPage가 있으면 nextButtonLabel 버튼 → nextPage
/// showLottoNumbers: true면 처음만 음성 재생, 이후 영상은 음소거·무한반복 백그라운드, 6개 색상 공 일렬에 추첨번호 표시
class VideoIntroPage extends StatefulWidget {
  final String title;
  final String assetPath;
  final CounselMode? mode;
  final Widget? nextPage;
  final String? nextButtonLabel;
  final bool showLottoNumbers;

  const VideoIntroPage({
    super.key,
    required this.title,
    required this.assetPath,
    this.mode,
    this.nextPage,
    this.nextButtonLabel,
    this.showLottoNumbers = false,
  });

  @override
  State<VideoIntroPage> createState() => _VideoIntroPageState();
}

class _VideoIntroPageState extends State<VideoIntroPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _errorMessage;
  bool _showLottoOverlay = false;
  List<int>? _lottoNumbers;

  /// 롤링 이펙트: 1~45 빠르게 바뀌다가 차례대로 멈춤
  List<int> _displayNumbers = List.filled(6, 1);
  List<int>? _finalNumbers;
  int _stoppedCount = 0;
  Timer? _rollTimer;
  Timer? _stopTimer;
  static final Random _random = Random();

  /// 추첨 기록 (회차별 6개 번호) — 앱 종료 후에도 유지
  final List<List<int>> _drawnHistory = [];
  static const String _prefKeyLottoVideoHistory = 'lotto_video_drawn_history';
  List<LottoWinningRow> _winningList = [];
  bool _winningLoading = true;

  void _cancelRollTimers() {
    _rollTimer?.cancel();
    _rollTimer = null;
    _stopTimer?.cancel();
    _stopTimer = null;
  }

  void _startRollingAnimation(List<int> finalSix) {
    _cancelRollTimers();
    _finalNumbers = List.from(finalSix);
    _stoppedCount = 0;
    _displayNumbers = List.generate(6, (_) => _random.nextInt(45) + 1);

    _rollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = _stoppedCount; i < 6; i++) {
          _displayNumbers[i] = _random.nextInt(45) + 1;
        }
      });
    });

    int stopped = 0;
    _stopTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
      if (!mounted) return;
      stopped++;
      if (stopped > 6) {
        _cancelRollTimers();
        setState(() => _stoppedCount = 6);
        return;
      }
      setState(() {
        _stoppedCount = stopped;
        for (int i = 0; i < stopped && i < 6; i++) {
          _displayNumbers[i] = _finalNumbers![i];
        }
      });
      if (stopped >= 6) _cancelRollTimers();
    });
  }

  Future<void> _loadDrawnHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyLottoVideoHistory);
      if (json == null) return;
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null) return;
      _drawnHistory.clear();
      for (final e in list) {
        final nums = (e as List<dynamic>).map((n) => n as int).toList();
        if (nums.length == 6) _drawnHistory.add(nums);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveDrawnHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKeyLottoVideoHistory,
        jsonEncode(_drawnHistory.map((e) => e).toList()),
      );
    } catch (_) {}
  }

  void _showLottoAndDraw() {
    if (!mounted || !widget.showLottoNumbers) return;
    final numbers = List<int>.generate(45, (i) => i + 1)..shuffle();
    final six = numbers.take(6).toList()..sort();
    _drawnHistory.add(List.from(six));
    _saveDrawnHistory();
    setState(() {
      _showLottoOverlay = true;
      _lottoNumbers = six;
    });
    _controller.setVolume(0);
    _controller.setLooping(true);
    _controller.play();
    _startRollingAnimation(six);
  }

  void _onVideoEnd() {
    if (!mounted || !widget.showLottoNumbers || _showLottoOverlay) return;
    _showLottoAndDraw();
  }

  Future<void> _skipToEndAndShowDraw() async {
    if (!_ready || !widget.showLottoNumbers) return;
    final dur = _controller.value.duration;
    if (dur == Duration.zero) return;
    await _controller.seekTo(dur - const Duration(milliseconds: 100));
    if (!_showLottoOverlay) _showLottoAndDraw();
  }

  void _onDrawAgain() {
    if (!_showLottoOverlay || _finalNumbers == null) return;
    final numbers = List<int>.generate(45, (i) => i + 1)..shuffle();
    final six = numbers.take(6).toList()..sort();
    _drawnHistory.add(List.from(six));
    _saveDrawnHistory();
    setState(() => _lottoNumbers = six);
    _startRollingAnimation(six);
  }

  void _clearDrawnHistory() {
    _drawnHistory.clear();
    _saveDrawnHistory();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();

    if (widget.showLottoNumbers) {
      _loadDrawnHistory();
      fetchLottoWinningList().then((list) {
        if (mounted) setState(() {
          _winningList = list;
          _winningLoading = false;
        });
      });
    }

    _controller = VideoPlayerController.asset(widget.assetPath)
      ..initialize().then((_) async {
        if (!mounted) return;
        if (_controller.value.hasError) {
          setState(() {
            _errorMessage = _controller.value.errorDescription ?? '영상 로드 실패';
          });
          return;
        }
        setState(() => _ready = true);
        try {
          await _controller.setVolume(1.0);
          await _controller.play();
        } catch (e) {
          debugPrint('영상 재생 오류: $e');
        }
        if (widget.showLottoNumbers) {
          _controller.addListener(_listenVideoEnd);
        }
      }).catchError((error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = '영상 파일을 불러올 수 없습니다: $error';
        });
        debugPrint('영상 초기화 오류: $error');
      });
  }

  void _listenVideoEnd() {
    if (!_ready || _controller.value.duration == Duration.zero) return;
    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    if (pos >= dur - const Duration(milliseconds: 200)) {
      _controller.removeListener(_listenVideoEnd);
      _onVideoEnd();
    }
  }

  @override
  void dispose() {
    if (_ready && widget.showLottoNumbers) {
      _controller.removeListener(_listenVideoEnd);
    }
    _cancelRollTimers();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white70,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : _ready
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final ar = _controller.value.aspectRatio;
                            double w = constraints.maxWidth;
                            double h = constraints.maxHeight;
                            if (ar > 0) {
                              if (ar > w / h) {
                                w = constraints.maxWidth;
                                h = w / ar;
                              } else {
                                h = constraints.maxHeight;
                                w = h * ar;
                              }
                            }
                            return Center(
                              child: SizedBox(
                                width: w,
                                height: h,
                                child: AspectRatio(
                                  aspectRatio: ar > 0 ? ar : 16 / 9,
                                  child: VideoPlayer(_controller),
                                ),
                              ),
                            );
                          },
                        )
                      : const CircularProgressIndicator(),
            ),

            // 로또: 6개 색상 공 일렬 + 추첨 번호 (화면 중간쯤에 배치해 버튼에 가리지 않게)
            if (widget.showLottoNumbers && _showLottoOverlay && _displayNumbers.length >= 6)
              Positioned(
                left: 16,
                right: 16,
                bottom: 280,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (i) {
                    const colors = [
                      Color(0xFFE53935), // 빨강
                      Color(0xFFFFEB3B), // 노랑
                      Color(0xFFFF9800), // 주황
                      Color(0xFF1E88E5),  // 파랑
                      Color(0xFF26A69A), // 청록
                      Color(0xFFECEFF1), // 흰/회색
                    ];
                    final color = colors[i];
                    return Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                            spreadRadius: 0,
                          ),
                          BoxShadow(
                            color: Colors.white24,
                            blurRadius: 2,
                            offset: const Offset(-1, -1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${_displayNumbers[i]}',
                          style: TextStyle(
                            color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            shadows: const [
                              Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(1, 1)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // 상단 제목 + 닫기
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 로또: 상단 추첨목록창 반으로 — 좌: 최근회차 1등 추첨번호(보너스 없음), 우: 추첨하기로 나온 번호
            if (widget.showLottoNumbers && _showLottoOverlay)
              Positioned(
                left: 8,
                right: 8,
                top: 52,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 150,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
                                    child: Text(
                                      '최근회차 1등 추첨번호',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _winningLoading
                                        ? const Center(child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                          ))
                                        : ListView.builder(
                                            padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
                                            physics: const BouncingScrollPhysics(),
                                            itemCount: _winningList.length > 10 ? 10 : _winningList.length,
                                            itemBuilder: (context, i) {
                                              final row = _winningList[i];
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE65100),
                                                    borderRadius: BorderRadius.circular(20),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black26,
                                                        blurRadius: 2,
                                                        offset: const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '${row.round}회',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Flexible(
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment.centerLeft,
                                                          child: Text(
                                                            row.numbers.join(', '),
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              color: Colors.white24,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                                    child: Text(
                                      '추첨 번호',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _drawnHistory.isEmpty
                                        ? Center(
                                            child: Text(
                                              '추첨 기록이 없습니다.',
                                              style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
                                            physics: const BouncingScrollPhysics(),
                                            itemCount: _drawnHistory.length,
                                            itemBuilder: (context, i) {
                                              final nums = _drawnHistory[i];
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1976D2),
                                                    borderRadius: BorderRadius.circular(20),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black26,
                                                        blurRadius: 2,
                                                        offset: const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '${i + 1}회',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Flexible(
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment.centerLeft,
                                                          child: Text(
                                                            nums.join(', '),
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                        child: TextButton.icon(
                          onPressed: _drawnHistory.isEmpty ? null : () {
                            SystemSound.play(SystemSoundType.click);
                            _clearDrawnHistory();
                          },
                          icon: const Icon(Icons.delete_sweep, color: Colors.white70, size: 20),
                          label: const Text(
                            '목록 초기화',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 하단 재생/일시정지 버튼 + 선택창으로 돌아가기 버튼
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 재생/일시정지 버튼
                  IconButton(
                    iconSize: 56,
                    onPressed: () {
                      if (!_ready) return;
                      if (_controller.value.isPlaying) {
                        _controller.pause();
                      } else {
                        _controller.play();
                      }
                      setState(() {});
                    },
                    icon: Icon(
                      _ready && _controller.value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white70,
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // 채팅 시작 / 로또: 추첨하기(단독·크게) + 구형추첨기로 이동
                  if (_ready && (widget.mode != null || widget.nextPage != null))
                    widget.showLottoNumbers && _showLottoOverlay
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    SystemSound.play(SystemSoundType.click);
                                    _onDrawAgain();
                                  },
                                  icon: const Icon(Icons.shuffle, color: Colors.white, size: 26),
                                  label: const Text(
                                    '추첨하기',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF9800),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      side: const BorderSide(
                                        color: Colors.white38,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    SystemSound.play(SystemSoundType.click);
                                    _controller.pause();
                                    _controller.setVolume(0);
                                    if (widget.nextPage != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => widget.nextPage!,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.confirmation_number, color: Colors.white),
                                  label: const Text(
                                    '구형추첨기로 이동',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE65100),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      side: const BorderSide(
                                        color: Colors.white38,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ElevatedButton.icon(
                            onPressed: () {
                              SystemSound.play(SystemSoundType.click);
                              _controller.pause();
                              _controller.setVolume(0);
                              if (widget.mode != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatPage(mode: widget.mode!),
                                  ),
                                );
                              } else if (widget.showLottoNumbers) {
                                _skipToEndAndShowDraw();
                              } else if (widget.nextPage != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => widget.nextPage!,
                                  ),
                                );
                              }
                            },
                            icon: Icon(
                              widget.mode != null ? Icons.chat_bubble : Icons.confirmation_number,
                              color: Colors.white,
                            ),
                            label: Text(
                              widget.mode != null
                                  ? '채팅 시작'
                                  : (widget.nextButtonLabel ?? '시작하기'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.mode == CounselMode.angel
                                  ? const Color(0xFF8EC5FC)
                                  : widget.mode == CounselMode.fact
                                      ? const Color(0xFF414345)
                                      : const Color(0xFFE65100),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: const BorderSide(
                                  color: Colors.white38,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                  const SizedBox(height: 12),
                  
                  // 선택창으로 돌아가기 버튼
                  if (_ready)
                    ElevatedButton.icon(
                      onPressed: () {
                        SystemSound.play(SystemSoundType.click);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      label: const Text(
                        '선택창으로 돌아가기',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: const BorderSide(
                            color: Colors.white38,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
