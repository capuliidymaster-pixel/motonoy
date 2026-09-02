import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'profile.dart';
import 'map.dart';
import 'add_motor.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int currentTab = 0;

  // === PER-ACCOUNT DATA (Firestore, keyed by uid — NOT shared across accounts) ===
  User? _currentUser;
  String riderName = "Rider";
  String motorcycleName = "Loading...";

  // === DEVICE-LEVEL PREFERENCE (fine to keep local — just a display setting) ===
  bool isDarkMode = true;
  bool isRefreshing = false;

  String gpsStatus = "Strong";
  int batteryLevel = 92;
  int lastPingMinutes = 2;

  late final AnimationController _radarController;

  // === MOTOGUARD DESIGN TOKENS ===
  // Ink console at night, cool daylight panel by day. Two functional accents
  // (signal teal = "watching", amber = caution) plus crimson reserved
  // strictly for SOS, so color always carries meaning instead of decorating.
  Color get _bg =>
      isDarkMode ? const Color(0xFF0A0E17) : const Color(0xFFEDF1F6);
  Color get _bg2 =>
      isDarkMode ? const Color(0xFF0D1220) : const Color(0xFFE4E9F0);

  Color get _panelStart => isDarkMode
      ? const Color(0xFF121826).withValues(alpha: 0.78)
      : Colors.white.withValues(alpha: 0.86);
  Color get _panelEnd => isDarkMode
      ? const Color(0xFF171E30).withValues(alpha: 0.55)
      : const Color(0xFFF7F9FC).withValues(alpha: 0.7);

  Color get _border => isDarkMode
      ? const Color(0xFF2A3346).withValues(alpha: 0.9)
      : const Color(0xFFD3DAE3);

  Color get _signal =>
      isDarkMode ? const Color(0xFF00E5C7) : const Color(0xFF00A88F);
  Color get _amber =>
      isDarkMode ? const Color(0xFFFFB020) : const Color(0xFFC97A00);
  Color get _crimson =>
      isDarkMode ? const Color(0xFFFF3B5C) : const Color(0xFFD8214A);

  Color get _text =>
      isDarkMode ? const Color(0xFFF4F6F9) : const Color(0xFF11151E);
  Color get _mist =>
      isDarkMode ? const Color(0xFF8A93A6) : const Color(0xFF5B6472);

  Color get _shadowColor => isDarkMode
      ? Colors.black.withValues(alpha: 0.35)
      : Colors.black.withValues(alpha: 0.08);

  String get currentDayName => DateFormat("EEEE").format(DateTime.now());
  String get currentDateFormatted => DateFormat("MMM d").format(DateTime.now());
  String get currentTimeFormatted => DateFormat("HH:mm").format(DateTime.now());

  String getGreeting() {
    var hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (!(WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations)) {
      _radarController.repeat();
    }
    _initializeApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadTheme();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    _currentUser = FirebaseAuth.instance.currentUser;
    await loadTheme();
    await _loadUserProfile();
    await _fetchLatestData();
  }

  Future<void> _fetchLatestData() async {
    setState(() => isRefreshing = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      gpsStatus = "Strong";
      isRefreshing = false;
    });
  }

  // Device-level display setting — fine to stay local, doesn't leak
  // between accounts since it's not personal/identifying data.
  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool("isDarkMode") ?? true;
    });
    _updateSystemUI();
  }

  void _updateSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: _bg,
        systemNavigationBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
      ),
    );
  }

  // === PER-ACCOUNT: pulled from Firestore doc keyed by the logged-in
  // user's uid, so each account only ever sees its own name/motorcycle,
  // even when multiple accounts log in on the same device. ===
  Future<void> _loadUserProfile() async {
    final user = _currentUser;
    if (user == null) {
      setState(() {
        riderName = "Rider";
        motorcycleName = "Honda XRM 125";
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();

      setState(() {
        riderName = data?['name'] ??
            user.displayName ??
            (user.email != null ? user.email!.split('@').first : "Rider");
        motorcycleName = data?['motorcycleName'] ?? "Honda XRM 125";
      });
    } catch (e) {
      setState(() {
        riderName = user.displayName ?? "Rider";
        motorcycleName = "Honda XRM 125";
      });
    }
  }

  // Writes to THIS user's Firestore doc only (doc id = uid) — never
  // touches or overwrites another account's data.
  Future<void> saveMotorcycleName(String newName) async {
    final user = _currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {'motorcycleName': newName},
      SetOptions(merge: true), // merge so we don't clobber name/email/etc.
    );

    setState(() {
      motorcycleName = newName;
    });
  }

  Future<void> nav(int i) async {
    setState(() {
      currentTab = i;
    });
    if (i == 0) return;

    if (i == 1) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const TrackPage()));
    }
    if (i == 2) {
      Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ProfilePage()))
          .then((_) => loadTheme());
    }
  }

  void snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDarkMode ? const Color(0xFF171E30) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          text,
          style: GoogleFonts.manrope(color: _text, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> openEditPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMotorPage(currentName: motorcycleName),
      ),
    );
    if (result != null) {
      await saveMotorcycleName(result.toString());
    }
  }

  // === TYPE HELPERS ===
  TextStyle _display({
    required double size,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.rajdhani(
      fontSize: size,
      fontWeight: weight,
      color: color ?? _text,
      letterSpacing: letterSpacing,
      height: 1.0,
    );
  }

  TextStyle _mono({
    required double size,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double letterSpacing = 1.0,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color ?? _mist,
      letterSpacing: letterSpacing,
    );
  }

  // === STATIC GRADIENT BACKGROUND (PERFORMANCE OPTIMIZED) ===
  Widget _buildStaticBackground() {
    return Container(
      color: _bg,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_bg, _bg2],
              ),
            ),
          ),
          Positioned(
            top: -110,
            right: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _signal.withValues(alpha: isDarkMode ? 0.07 : 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -130,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _amber.withValues(alpha: isDarkMode ? 0.05 : 0.04),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          _buildStaticBackground(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    color: _signal,
                    backgroundColor: _panelStart,
                    onRefresh: _fetchLatestData,
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        const SizedBox(height: 16),
                        _header(),
                        _guardConsoleCard(),
                        _quickActions(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                _bottomNav(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // === HEADER (single line) ===
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _signal.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _signal.withValues(alpha: 0.3)),
                ),
                child:
                    Icon(Icons.shield_moon_rounded, color: _signal, size: 18),
              ),
              const SizedBox(width: 10),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                        text: "MOTO",
                        style: _display(
                            size: 18,
                            weight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: _text)),
                    TextSpan(
                        text: "GUARD",
                        style: _display(
                            size: 18,
                            weight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: _signal)),
                  ],
                ),
              ),
            ],
          ),
          Text(
            // ✅ Now shows the actual registered name per account,
            // instead of a hardcoded "Rider" for everyone.
            "${getGreeting()}, $riderName",
            style: _mono(size: 11.5, color: _mist, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }

  // === GUARD CONSOLE (motorcycle card) ===
  Widget _guardConsoleCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_panelStart, _panelEnd],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _border, width: 1.2),
        boxShadow: [
          BoxShadow(
              color: _shadowColor, blurRadius: 26, offset: const Offset(0, 12))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _signal.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _signal.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _signal,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: _signal.withValues(alpha: 0.7),
                              blurRadius: 5)
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text("ACTIVE GUARD",
                        style: _mono(
                            size: 11,
                            weight: FontWeight.w700,
                            color: _signal,
                            letterSpacing: 1.2)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: openEditPage,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _amber.withValues(alpha: 0.25)),
                  ),
                  child: Icon(Icons.edit_rounded, color: _amber, size: 19),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text("YOUR MOTORCYCLE",
              style: _mono(size: 11.5, color: _mist, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          Text(
            motorcycleName,
            style: _display(
                size: 30, weight: FontWeight.w700, letterSpacing: -0.3),
          ),
          const SizedBox(height: 20),
          Center(child: _radarBike()),
          const SizedBox(height: 20),
          _telemetryStrip(),
        ],
      ),
    );
  }

  // Signature element: radar pulse rings behind the bike — "this bike is
  // being watched", refreshed every 3s. The chip underneath labels the
  // graphic so it reads as a live guarded view, not decoration.
  Widget _radarBike() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 168,
          width: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _radarController,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(168, 168),
                    painter: _RadarPainter(
                        progress: _radarController.value, color: _signal),
                  );
                },
              ),
              Container(
                constraints:
                    const BoxConstraints(maxHeight: 108, maxWidth: 140),
                child: Image.asset(
                  "assets/bike.png",
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 96,
                      width: 96,
                      decoration: BoxDecoration(
                        color: _signal.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: _signal.withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.motorcycle_rounded,
                          size: 46, color: _signal),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _signal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _signal.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _signal,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: _signal.withValues(alpha: 0.7), blurRadius: 4)
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text("LIVE VIEW",
                  style: _mono(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: _signal,
                      letterSpacing: 1.1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _telemetryStrip() {
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
              child: _telemetryStat("GPS", gpsStatus.toUpperCase(), _signal)),
          Container(width: 1, height: 30, color: _border),
          Expanded(child: _telemetryStat("BATTERY", "$batteryLevel%", _amber)),
          Container(width: 1, height: 30, color: _border),
          Expanded(
              child: _telemetryStat(
                  "LAST PING", "${lastPingMinutes}M AGO", _mist)),
        ],
      ),
    );
  }

  Widget _telemetryStat(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _mono(size: 9.5, color: _mist, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value,
              style: _mono(size: 13.5, weight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // === QUICK ACTIONS ===
  Widget _quickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(
              child: _actionCard(
                  Icons.explore_rounded, "LIVE\nTRACK", _signal, () => nav(1))),
          const SizedBox(width: 12),
          Expanded(
              child: _actionCard(Icons.shield_rounded, "SECURITY\nMODE", _amber,
                  () => snack("Security mode activated"))),
          const SizedBox(width: 12),
          Expanded(
              child: _actionCard(
                  Icons.emergency_share_rounded,
                  "EMERGENCY\nSOS",
                  _crimson,
                  () => snack("Emergency SOS broadcast sent"))),
        ],
      ),
    );
  }

  Widget _actionCard(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: _panelStart,
            border: Border.all(color: _border, width: 1),
          ),
          child: Column(
            children: [
              // Thin top accent bar — color encodes what kind of action this
              // is (teal = tracking, amber = caution, crimson = emergency).
              Container(height: 3, color: color),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            shape: BoxShape.circle),
                        child: Icon(icon, size: 26, color: color),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: _mono(
                              size: 10.5,
                              weight: FontWeight.w700,
                              color: _text,
                              letterSpacing: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // === BOTTOM NAV ===
  Widget _bottomNav() {
    return Container(
      height: 74,
      margin: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _panelStart,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border, width: 1.2),
        boxShadow: [
          BoxShadow(
              color: _shadowColor, blurRadius: 20, offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.grid_view_rounded, "HOME", 0),
          _navItem(Icons.map_rounded, "MAP", 1),
          _navItem(Icons.person_rounded, "PROFILE", 2),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = currentTab == i;
    return GestureDetector(
      onTap: () => nav(i),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _signal.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? _signal : _mist, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: _mono(
                  size: 9.5,
                  weight: FontWeight.w700,
                  color: active ? _signal : _mist,
                  letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints three concentric rings expanding outward and fading — the
/// "actively watched" signature motif behind the bike.
class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (int i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = maxRadius * t;
      final opacity = (1 - t).clamp(0.0, 1.0) * 0.55;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
