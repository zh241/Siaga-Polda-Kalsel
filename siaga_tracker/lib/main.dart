import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// Global ValueNotifier for ThemeMode
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// Forced dark theme settings for initial/auth screens
final ThemeData forceDarkTheme = ThemeData.dark().copyWith(
  primaryColor: const Color(0xFF3B82F6),
  scaffoldBackgroundColor: const Color(0xFF0F121A),
  cardColor: const Color(0xFF18181B),
  dividerColor: const Color(0xFF27272A),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF18181B),
    foregroundColor: Colors.white,
    elevation: 1,
    titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    iconTheme: IconThemeData(color: Colors.white),
  ),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF3B82F6),
    surface: Color(0xFF18181B),
    onSurface: Colors.white,
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Menyalakan Mesin Firebase
  
  // Load saved theme mode
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode');
    if (savedTheme == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    }
  } catch (e) {
    debugPrint('Error loading saved theme: $e');
  }
  
  runApp(const SigapApp());
}

class SigapApp extends StatelessWidget {
  const SigapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'SIAGA Mobile Tracker',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF3B82F6),
            scaffoldBackgroundColor: const Color(0xFFF4F4F5),
            cardColor: const Color(0xFFFFFFFF),
            dividerColor: const Color(0xFFE4E4E7),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFFFFFF),
              foregroundColor: Colors.black,
              elevation: 1,
              titleTextStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              iconTheme: IconThemeData(color: Colors.black),
            ),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
              surface: Color(0xFFFFFFFF),
              onSurface: Colors.black,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            primaryColor: const Color(0xFF3B82F6),
            scaffoldBackgroundColor: const Color(0xFF09090B),
            cardColor: const Color(0xFF18181B),
            dividerColor: const Color(0xFF27272A),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF18181B),
              foregroundColor: Colors.white,
              elevation: 1,
              titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              iconTheme: IconThemeData(color: Colors.white),
            ),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF3B82F6),
              surface: Color(0xFF18181B),
              onSurface: Colors.white,
            ),
          ),
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// ============================================================================
// AUTH WRAPPER - Cek status login Firebase
// ============================================================================
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _splashDone = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;

      return Scaffold(
        body: GridBackground(
          imageOpacity: 0.55,
          showGrid: false,
          child: SafeArea(
            child: Column(
              children: [
                const TopLogos(),
                const Spacer(),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'SIAGA',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'SISTEM INFORMASI\nAKTIVITAS DAN GERAK\nANGGOTA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFC0C4D6) : Colors.black54,
                          letterSpacing: 1.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF0D6EFD)),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return DashboardScreen(user: snapshot.data!);
        }
        return const WelcomeScreen();
      },
    );
  }
}

// ============================================================================
// WIDGET UTULITAS & TAMPILAN GRAFIS PRESTISE SIAGA
// ============================================================================
class GridBackground extends StatelessWidget {
  final Widget child;
  final double imageOpacity;
  final bool forceDark;
  final bool showGrid;
  const GridBackground({
    super.key,
    required this.child,
    this.imageOpacity = 0.0,
    this.forceDark = false,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = forceDark || theme.brightness == Brightness.dark;
    final bgColor = forceDark ? const Color(0xFF0F121A) : theme.scaffoldBackgroundColor;
    final gridColor = isDark
        ? const Color(0xFF3B82F6).withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.02);

    return Stack(
      children: [
        Container(color: bgColor),
        if (showGrid)
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(color: gridColor),
            ),
          ),
        if (imageOpacity > 0.0)
          Positioned.fill(
            child: Image.asset(
              'assets/bg_gedung.jpg',
              fit: BoxFit.cover,
              opacity: AlwaysStoppedAnimation(isDark ? imageOpacity : imageOpacity * 0.15),
              errorBuilder: (context, error, stackTrace) {
                debugPrint("Background asset error: $error");
                return const SizedBox.shrink();
              },
            ),
          ),
        if (imageOpacity > 0.0)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isDark ? Colors.black.withValues(alpha: 0.35) : Colors.transparent,
                  bgColor,
                ],
              ),
            ),
          ),
        child,
      ],
    );
  }
}

class GridPainter extends CustomPainter {
  final Color color;
  GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    const double step = 25.0;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) => oldDelegate.color != color;
}

class ShieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.6);
    path.quadraticBezierTo(
      size.width, size.height * 0.85,
      size.width * 0.5, size.height,
    );
    path.quadraticBezierTo(
      0, size.height * 0.85,
      0, size.height * 0.6,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, size.width * 0.45, paint);
    canvas.drawCircle(center, size.width * 0.3, paint);
    canvas.drawCircle(center, size.width * 0.15, paint);

    canvas.drawLine(Offset(center.dx - size.width * 0.5, center.dy), Offset(center.dx + size.width * 0.5, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - size.height * 0.5), Offset(center.dx, center.dy + size.height * 0.5), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TikPolriShieldLogo extends StatelessWidget {
  final double size;
  const TikPolriShieldLogo({super.key, this.size = 110});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo_tik.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.shield, color: Colors.blueAccent, size: size);
      },
    );
  }
}

class TopLogos extends StatelessWidget {
  const TopLogos({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(
            'assets/logo_polda.png',
            width: 52,
            height: 60,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/e/ea/Lambang_Polda_Kalsel.png',
              width: 52,
              height: 60,
              fit: BoxFit.contain,
              errorBuilder: (context, err, st) => Container(
                width: 52,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.blue, size: 24),
              ),
            ),
          ),
          Image.asset(
            'assets/logo_tik.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d4/Logo_Polri.png/200px-Logo_Polri.png',
              width: 38,
              height: 38,
              fit: BoxFit.contain,
              errorBuilder: (context, err, st) => Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.security, color: Colors.red, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.greenAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ============================================================================
// HALAMAN 1A: WELCOME SCREEN (SPLASH & MENU UTAMA)
// ============================================================================
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final bool _showButtons = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GridBackground(
        imageOpacity: 0.55,
        showGrid: false,
        child: SafeArea(
          child: Column(
            children: [
              const TopLogos(),
              const Spacer(),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'SIAGA',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black87,
                        letterSpacing: 4.0,
                        shadows: isDark
                            ? [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  offset: const Offset(0, 4),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'SISTEM INFORMASI\nAKTIVITAS DAN GERAK\nANGGOTA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFC0C4D6) : Colors.black54,
                        letterSpacing: 1.8,
                        height: 1.6,
                        shadows: isDark
                            ? [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  offset: const Offset(0, 2),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                opacity: _showButtons ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 800),
                child: _showButtons
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25.0),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF922020),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 4,
                                  shadowColor: const Color(0xFF922020).withValues(alpha: 0.4),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'MASUK',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: isDark ? Colors.white : const Color(0xFF922020),
                                  side: BorderSide(
                                    color: isDark 
                                        ? Colors.white.withValues(alpha: 0.35) 
                                        : const Color(0xFF922020).withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const RegisterScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'DAFTAR AKUN',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 25),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark 
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isDark 
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.08),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock,
                                    color: isDark ? Colors.greenAccent : Colors.green,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'KONEKSI AMAN TERJALIN',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isDark 
                                          ? Colors.white.withValues(alpha: 0.7)
                                          : Colors.black54,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(height: 169),
              ),
              const SizedBox(height: 25),
              Text(
                'PROYEK SIAGA - VERSI 1.0',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? const Color(0xFF64748B) : Colors.black38,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HALAMAN 1B: LOGIN SCREEN
// ============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nrpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _loginWithFirebase() async {
    final String nrpInput = _nrpController.text.trim();
    final String password = _passwordController.text;

    if (nrpInput.isEmpty || password.isEmpty) {
      _showSnackBar('NRP dan kata sandi tidak boleh kosong!', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    
    final String email = nrpInput.contains('@') ? nrpInput : '$nrpInput@siaga.polri.go.id';

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      String errMsg = 'NRP atau kata sandi salah!';
      if (e.code == 'invalid-email') errMsg = 'Format NRP tidak valid.';
      _showSnackBar(errMsg, Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  void _lupaPasswordDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: theme.dividerColor),
        ),
        title: Text(
          'Lupa Kata Sandi?',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Demi keamanan sistem, proses reset kata sandi wajib dilakukan secara langsung melalui Layanan Dukungan IT Bid TIK Polda Kalsel di Markas Kepolisian.',
          style: TextStyle(color: isDark ? Colors.grey : Colors.black54, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFFC0C4D6) : const Color(0xFF3B82F6),
              foregroundColor: isDark ? Colors.black : Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GridBackground(
        imageOpacity: 0.55,
        showGrid: false,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                children: [
                  const TopLogos(),
                  const SizedBox(height: 35),
                  Text(
                    'SIAGA',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'SISTEM INFORMASI AKTIVITAS DAN GERAK\nANGGOTA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFC0C4D6) : Colors.black54,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 35),
                  
                  Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NRP',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nrpController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Masukkan NRP',
                            hintStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: const Icon(Icons.badge_outlined, color: Colors.grey),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        const Text(
                          'KATA SANDI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            hintStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: const Icon(Icons.lock_outlined, color: Colors.grey),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: InkWell(
                            onTap: _lupaPasswordDialog,
                            child: const Text(
                              'Lupa Password?',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF922020),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 4,
                              shadowColor: const Color(0xFF922020).withValues(alpha: 0.4),
                            ),
                            onPressed: _isLoading ? null : _loginWithFirebase,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Text(
                                        'MASUK',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.login, size: 18),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 35),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      PulsingDot(),
                      SizedBox(width: 8),
                      Text(
                        'SERVER AKTIF',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'BID TIK POLDA KALSEL',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: isDark ? Colors.grey : Colors.black38,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 25),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nrpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// ============================================================================
// HALAMAN 1C: REGISTRASI SCREEN
// ============================================================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nrpController = TextEditingController();
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _pangkatController = TextEditingController();
  final TextEditingController _jabatanController = TextEditingController();
  final TextEditingController _satkerController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _registerWithFirebase() async {
    final String nrp = _nrpController.text.trim();
    final String nama = _namaController.text.trim();
    final String pangkat = _pangkatController.text.trim();
    final String jabatan = _jabatanController.text.trim();
    final String satker = _satkerController.text.trim();
    final String email = _emailController.text.trim();
    final String phone = _phoneController.text.trim();
    final String password = _passwordController.text;

    if (nrp.isEmpty ||
        nama.isEmpty ||
        pangkat.isEmpty ||
        jabatan.isEmpty ||
        satker.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        password.isEmpty) {
      _showSnackBar('Harap isi semua kolom wajib!', Colors.red);
      return;
    }

    if (password.length < 8) {
      _showSnackBar('Kata sandi minimal harus 8 karakter!', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    final String virtualEmail = '$nrp@siaga.polri.go.id';

    try {
      final UserCredential userCred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: virtualEmail,
        password: password,
      );

      final DatabaseReference dbRef = FirebaseDatabase.instance.ref('users');
      await dbRef.child(userCred.user!.uid).set({
        'nrp': nrp,
        'nama': nama,
        'pangkat': pangkat,
        'jabatan': jabatan,
        'satker': satker,
        'email': email,
        'no_hp_dinas': phone,
        'role': 'member',
        'status': 'pending',
        'waktu_daftar': DateTime.now().toIso8601String(),
      });

      _showSnackBar('Registrasi Berhasil! Hubungi admin untuk verifikasi.', Colors.green);
      
      await Future.delayed(const Duration(seconds: 2));
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Registrasi Gagal: ${e.message}';
      if (e.code == 'email-already-in-use') {
        msg = 'NRP ini sudah terdaftar.';
      }
      _showSnackBar(msg, Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GridBackground(
        showGrid: false,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                children: [
                  const TopLogos(),
                  const SizedBox(height: 25),
                  Text(
                    'REGISTRASI PERSONEL',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Sistem Informasi Aktivitas dan Gerak Anggota',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 25),
                  
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NOMOR REGISTRASI POKOK (NRP)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nrpController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Masukkan NRP',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.badge_outlined, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        const Text('NAMA LENGKAP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _namaController,
                          textCapitalization: TextCapitalization.words,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'SESUAI KTP/KTA',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.person_outline, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        const Text('PANGKAT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _pangkatController,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'CONTOH: BRIPDA / KOMBES',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.military_tech_outlined, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        const Text('JABATAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _jabatanController,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'CONTOH: BANUM / KANIT / KASUBDIT',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.work_outline, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        const Text('KESATUAN / SATKER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _satkerController,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'CONTOH: DITRESKRIMSUS',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.business_outlined, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        const Text('EMAIL PRIBADI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'contoh@email.com',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        const Text('NOMOR HP / WHATSAPP AKTIF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'CONTOH: 08123456789',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.phone_android_outlined, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        const Text('KATA SANDI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Minimal 8 karakter',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            prefixIcon: const Icon(Icons.lock_outlined, color: Colors.grey, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: Colors.grey,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.info_outline, color: Colors.orangeAccent, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pendaftaran akan diverifikasi oleh Admin sebelum akun diaktifkan.',
                                  style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF922020),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 4,
                              shadowColor: const Color(0xFF922020).withValues(alpha: 0.4),
                            ),
                            onPressed: _isLoading ? null : _registerWithFirebase,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Text(
                                        'AJUKAN PENDAFTARAN',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.person_add_alt_1_outlined, size: 16),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Sudah memiliki akses? Masuk di sini',
                      style: TextStyle(color: Color(0xFF3B82F6), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.verified_user_outlined, color: Colors.grey, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'KONEKSI AMAN TERENKRIPSI',
                        style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nrpController.dispose();
    _namaController.dispose();
    _pangkatController.dispose();
    _jabatanController.dispose();
    _satkerController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// ============================================================================

// ============================================================================
// HALAMAN 2: DASHBOARD UTAMA DENGAN NAVIGASI 4 MENU (SIAGA)
// ============================================================================
enum HomeMissionState { standby, formData, active }

class DashboardScreen extends StatefulWidget {
  final User user;
  const DashboardScreen({super.key, required this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  HomeMissionState _homeState = HomeMissionState.standby;

  String _getRoleDisplayName(String? role) {
    if (role == null) return '';
    switch (role.toLowerCase()) {
      case 'commander':
        return 'KOMANDAN';
      case 'member':
        return 'ANGGOTA';
      case 'admin':
        return 'ADMIN';
      default:
        return role.toUpperCase();
    }
  }

  late AnimationController _radarAnimationController;

  // Profil Data
  bool _checkingStatus = true;
  String _status = 'pending';
  String _nrp = '';
  String _nama = '';
  String _pangkat = '';
  String _jabatan = '';
  String _satker = '';
  String _role = 'member';
  String _fotoProfil = '';
  final Battery _battery = Battery();
  int _batteryLevel = 85;
  StreamSubscription<BatteryState>? _batterySubscription;

  // Real-time hardware and network status flags
  bool _gpsEnabled = true;
  bool _internetConnected = true;
  bool _isCharging = false;
  StreamSubscription<ServiceStatus>? _gpsStatusSubscription;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;

  // Variabel tracking
  bool _isTracking = false;
  Position? _posisiSekarang;
  StreamSubscription<Position>? _positionStream;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _pesanStream;

  // Form input pra-operasi
  final TextEditingController _commanderController = TextEditingController();
  final TextEditingController _personnelController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _opCodeController = TextEditingController();
  final TextEditingController _activityTypeController = TextEditingController();
  final TextEditingController _vehicleTypeController = TextEditingController();
  final TextEditingController _customVehicleController = TextEditingController();
  final TextEditingController _chatMsgController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  // DM state
  String _chatLevel = 'list'; // 'list' or 'conversation'
  String _chatPath = 'chat/umum'; // Firebase path for current chat
  String _dmConvId = ''; // conversation ID for DM
  String _dmTargetName = ''; // Display name of DM target
  Map<String, int> _lastReadMap = {};
  bool _anyUnreadDms = false;
  bool _anyUnreadPublic = false;
  int _lastReadUmum = 0;
  StreamSubscription<DatabaseEvent>? _dmSubscription;
  StreamSubscription<DatabaseEvent>? _umumChatSubscription;
  Map<String, dynamic> _latestDmData = {};
  String _selectedVehicleCategory = 'Jalan Kaki';
  String _noHpDinas = '';

  // Timer misi aktif
  Timer? _missionTimer;
  int _elapsedSeconds = 0;
  DateTime? _missionStartTime;

  // Data riwayat
  List<Map<String, dynamic>> _myHistory = [];
  StreamSubscription<DatabaseEvent>? _historyStream;

  // Geofence / Posko data (Fase 6)
  StreamSubscription<DatabaseEvent>? _geofencesSubscription;
  List<Map<String, dynamic>> _geofences = [];
  StreamSubscription<DatabaseEvent>? _settingsSubscription;
  StreamSubscription<DatabaseEvent>? _userSubscription;
  int _gpsInterval = 10;
  bool _maintenanceMode = false;
  DateTime? _lastFirebaseWriteTime;

  // Sesi pelacakan aktif (Task 41 & 42)
  final List<Position> _sessionTrackingPositions = [];
  double _sessionDistanceTraveled = 0.0;

  // Timer fallback untuk pelacakan lokasi jika stream bermasalah
  Timer? _fallbackLocationTimer;

  @override
  void initState() {
    super.initState();
    _radarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _getBatteryState();
    _checkStatusDanInisialisasi();
    _setupStatusListeners();
    _dengarkanGeofences();
    _dengarkanSettings();
    _dengarkanStatusAkun();
    _loadLastReadAndListenDms();
  }

  void _setupStatusListeners() {
    // 1. GPS Service Status Check & Listener
    Geolocator.isLocationServiceEnabled().then((enabled) {
      if (mounted) {
        setState(() {
          _gpsEnabled = enabled;
        });
      }
    });

    _gpsStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
      if (mounted) {
        setState(() {
          _gpsEnabled = (status == ServiceStatus.enabled);
        });
      }
    });

    // 2. Internet / Firebase Connection Check & Listener
    _connectionSubscription = _dbRef.child('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      if (mounted) {
        setState(() {
          _internetConnected = connected;
        });
      }
    });
  }

  void _dengarkanGeofences() {
    _geofencesSubscription?.cancel();
    _geofencesSubscription = _dbRef.child('geofences').onValue.listen((event) {
      final List<Map<String, dynamic>> temp = [];
      if (event.snapshot.value != null) {
        try {
          final Map<dynamic, dynamic> raw = event.snapshot.value as Map;
          raw.forEach((key, val) {
            if (val is Map) {
              final Map<String, dynamic> item = Map<String, dynamic>.from(val);
              item['id'] = key.toString();
              temp.add(item);
            }
          });
        } catch (e) {
          debugPrint('Error parsing geofences: $e');
        }
      }
      if (mounted) {
        setState(() {
          _geofences = temp;
        });
      }
    });
  }

  void _dengarkanSettings() {
    _settingsSubscription?.cancel();
    _settingsSubscription = _dbRef.child('system_settings').onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final Map<dynamic, dynamic> val = event.snapshot.value as Map;
          final int? interval = int.tryParse(val['gps_interval']?.toString() ?? '');
          final bool? maint = val['maintenance_mode'] as bool?;
          
          if (mounted) {
            setState(() {
              if (interval != null) _gpsInterval = interval;
              if (maint != null) {
                _maintenanceMode = maint;
                if (_maintenanceMode && _isTracking) {
                  _selesaiTugasPatroli();
                  _showSnackBar('Pelacakan dinonaktifkan otomatis: Mode Pemeliharaan Aktif.', Colors.red);
                }
              }
            });
          }
        } catch (e) {
          debugPrint('Error parsing system settings: $e');
        }
      }
    });
  }

  void _dengarkanStatusAkun() {
    _userSubscription?.cancel();
    _userSubscription = _dbRef.child('users/${widget.user.uid}').onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final Map<dynamic, dynamic> data = event.snapshot.value as Map;
          final String status = data['status']?.toString() ?? 'pending';
          if (status != 'active') {
            if (mounted) {
              setState(() {
                _status = status;
              });
            }
            if (_isTracking) {
              _selesaiTugasPatroli();
              _showSnackBar('Pelacakan dinonaktifkan otomatis: Status Akun Nonaktif.', Colors.red);
            }
          } else {
            // Update local fields in case admin edited them
            if (mounted) {
              setState(() {
                _status = 'active';
                _nama = data['nama']?.toString() ?? _nama;
                _nrp = data['nrp']?.toString() ?? _nrp;
                _pangkat = data['pangkat']?.toString() ?? _pangkat;
                _satker = data['satker']?.toString() ?? _satker;
              });
            }
          }
        } catch (e) {
          debugPrint('Error parsing status check: $e');
        }
      } else {
        // User deleted from DB
        if (mounted) {
          setState(() {
            _status = 'deleted';
          });
        }
        if (_isTracking) {
          _selesaiTugasPatroli();
          _showSnackBar('Akun Anda telah dinonaktifkan/dihapus.', Colors.red);
        }
      }
    });
  }

  Future<void> _getBatteryState() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _isCharging = (state == BatteryState.charging);
        });
      }
      _batterySubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
        final curLevel = await _battery.batteryLevel;
        if (mounted) {
          setState(() {
            _batteryLevel = curLevel;
            _isCharging = (state == BatteryState.charging);
          });
        }
      });
    } catch (e) {
      debugPrint("Error reading battery: $e");
    }
  }

  Future<void> _checkStatusDanInisialisasi() async {
    try {
      final snapshot = await _dbRef.child('users/${widget.user.uid}').get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          _nrp = data['nrp'] ?? '';
          _nama = data['nama'] ?? '';
          _pangkat = data['pangkat'] ?? '';
          _jabatan = data['jabatan'] ?? '';
          _satker = data['satker'] ?? '';
          _role = data['role'] ?? 'member';
          _status = data['status'] ?? 'pending';
          _fotoProfil = data['foto_profil'] ?? '';
          _noHpDinas = data['no_hp_dinas'] ?? '';
          _checkingStatus = false;
        });

        if (_status == 'active') {
          _pasangRadarPesan();
          _dengarkanRiwayatSelesai();
          _muatStateTrackingDariPrefs();
        }
      } else {
        setState(() {
          _status = 'pending';
          _checkingStatus = false;
        });
      }
    } catch (e) {
      debugPrint('Error status check: $e');
      setState(() {
        _status = 'pending';
        _checkingStatus = false;
      });
    }
  }

  Future<void> _loadLastReadAndListenDms() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final newMap = <String, int>{};
    for (final key in keys) {
      if (key.startsWith('dm_last_read_')) {
        final convId = key.replaceFirst('dm_last_read_', '');
        newMap[convId] = prefs.getInt(key) ?? 0;
      }
    }
    final readUmum = prefs.getInt('umum_last_read') ?? 0;

    if (mounted) {
      setState(() {
        _lastReadMap = newMap;
        _lastReadUmum = readUmum;
      });
    }

    // Now start listening to DMs
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (myUid.isEmpty) return;

    _dmSubscription = FirebaseDatabase.instance.ref('chat/dm').onValue.listen((event) {
      if (event.snapshot.value == null) {
        _latestDmData = {};
        _updateAnyUnreadDms({});
        return;
      }
      try {
        final raw = Map<String, dynamic>.from(event.snapshot.value as Map);
        _latestDmData = raw;
        _updateAnyUnreadDms(raw);
      } catch (e) {
        debugPrint('Error parsing DMs for unread badges: $e');
      }
    });

    // Also listen to chat/umum for unread notifications
    _umumChatSubscription = FirebaseDatabase.instance.ref('chat/umum').onValue.listen((event) {
      if (event.snapshot.value == null) {
        if (mounted) {
          setState(() {
            _anyUnreadPublic = false;
          });
        }
        return;
      }
      try {
        final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        bool unreadFound = false;
        raw.forEach((key, val) {
          if (val is Map) {
            final msgTimeStr = val['waktu']?.toString() ?? '';
            if (msgTimeStr.isNotEmpty) {
              DateTime? parsedTime;
              try {
                parsedTime = DateTime.parse(msgTimeStr);
              } catch (_) {}
              if (parsedTime != null) {
                final msgTime = parsedTime.millisecondsSinceEpoch;
                final msgUid = val['uid']?.toString() ?? '';
                
                if (_chatPath == 'chat/umum' && _chatLevel == 'conversation' && _currentIndex == 1) {
                  if (msgTime > _lastReadUmum) {
                    _lastReadUmum = msgTime;
                    SharedPreferences.getInstance().then((p) {
                      p.setInt('umum_last_read', msgTime);
                    });
                  }
                } else {
                  if (msgUid != myUid && msgTime > _lastReadUmum) {
                    unreadFound = true;
                  }
                }
              }
            }
          }
        });
        if (mounted) {
          setState(() {
            _anyUnreadPublic = unreadFound;
          });
        }
      } catch (e) {
        debugPrint('Error parsing public chat for unread: $e');
      }
    });
  }

  void _updateAnyUnreadDms(Map<String, dynamic> rawDms) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (myUid.isEmpty) return;

    bool unreadFound = false;
    rawDms.forEach((convId, data) {
      if (data is Map) {
        final conv = Map<String, dynamic>.from(data);
        final participants = conv['participants'] as Map?;
        if (participants != null && participants[myUid] == true) {
          final updatedAt = conv['updatedAt'] ?? 0;
          
          // If we are currently inside this conversation, we don't count it as unread,
          // AND we update our local last read to match updatedAt to avoid clock skew
          if (convId == _dmConvId && _chatLevel == 'conversation' && _currentIndex == 1) {
            final lastRead = _lastReadMap[convId] ?? 0;
            if (updatedAt > lastRead) {
              final now = DateTime.now().millisecondsSinceEpoch;
              final newRead = updatedAt > now ? updatedAt : now;
              _lastReadMap[convId] = newRead;
              SharedPreferences.getInstance().then((prefs) {
                prefs.setInt('dm_last_read_$convId', newRead);
              });
            }
            return; // Skip counting this as unread
          }
          
          final lastSender = conv['lastSender'];
          final isFromOther = lastSender == null || lastSender != myUid;
          if (isFromOther) {
            final lastRead = _lastReadMap[convId] ?? 0;
            if (updatedAt > lastRead) {
              unreadFound = true;
            }
          }
        }
      }
    });
    if (mounted) {
      setState(() {
        _anyUnreadDms = unreadFound;
      });
    }
  }

  Future<void> _simpanStateTrackingKePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_tracking_active', true);
      await prefs.setString('tracking_op_code', _opCodeController.text);
      await prefs.setString('tracking_activity_type', _activityTypeController.text);
      await prefs.setString('tracking_vehicle_type', _vehicleTypeController.text);
      await prefs.setString('tracking_commander', _commanderController.text);
      await prefs.setString('tracking_personnel_count', _personnelController.text);
      await prefs.setString('tracking_description', _descriptionController.text);
      await prefs.setString('tracking_start_time', _missionStartTime?.toIso8601String() ?? DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Error saving tracking state: $e');
    }
  }

  Future<void> _hapusStateTrackingDariPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_tracking_active');
      await prefs.remove('tracking_op_code');
      await prefs.remove('tracking_activity_type');
      await prefs.remove('tracking_vehicle_type');
      await prefs.remove('tracking_commander');
      await prefs.remove('tracking_personnel_count');
      await prefs.remove('tracking_description');
      await prefs.remove('tracking_start_time');
    } catch (e) {
      debugPrint('Error clearing tracking state: $e');
    }
  }

  Future<void> _muatStateTrackingDariPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool('is_tracking_active') ?? false;
      if (isActive && mounted) {
        final opCode = prefs.getString('tracking_op_code') ?? '';
        final activityType = prefs.getString('tracking_activity_type') ?? '';
        final vehicleType = prefs.getString('tracking_vehicle_type') ?? '';
        final commander = prefs.getString('tracking_commander') ?? '';
        final personnelCount = prefs.getString('tracking_personnel_count') ?? '';
        final description = prefs.getString('tracking_description') ?? '';
        final startTimeStr = prefs.getString('tracking_start_time');
        
        setState(() {
          _opCodeController.text = opCode;
          _activityTypeController.text = activityType;
          _vehicleTypeController.text = vehicleType;
          
          const allowed = ['Jalan Kaki', 'Sepeda Motor', 'Mobil', 'Truk', 'Bus'];
          if (allowed.contains(vehicleType)) {
            _selectedVehicleCategory = vehicleType;
            _customVehicleController.clear();
          } else if (vehicleType.isNotEmpty) {
            _selectedVehicleCategory = 'Lainnya';
            _customVehicleController.text = vehicleType;
          } else {
            _selectedVehicleCategory = 'Jalan Kaki';
            _customVehicleController.clear();
          }
          
          _commanderController.text = commander;
          _personnelController.text = personnelCount;
          _descriptionController.text = description;
          _missionStartTime = startTimeStr != null ? DateTime.tryParse(startTimeStr) : DateTime.now();
          _elapsedSeconds = DateTime.now().difference(_missionStartTime ?? DateTime.now()).inSeconds;
          if (_elapsedSeconds < 0) _elapsedSeconds = 0;
        });

        // Aktifkan kembali pelacakan (gunakan real tracking)
        _aktifkanTrackingSatelit();
      }
    } catch (e) {
      debugPrint('Error loading tracking state: $e');
    }
  }

  void _pasangRadarPesan() {
    _pesanStream = _dbRef.child('messages').limitToLast(1).onChildAdded.listen(
      (event) {
        if (event.snapshot.value != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final target = data['target'] ?? 'ALL UNITS';
          if (target == 'ALL UNITS' || target == _satker || target == 'POL-$_nrp') {
            _munculkanPeringatanKomando(
              data['pesan'] ?? 'Pesan instruksi komando baru.',
              data['oleh'] ?? 'Admin',
              data['waktu'] ?? 'Baru saja'
            );
          }
        }
      },
    );
  }

  void _dengarkanRiwayatSelesai() {
    _historyStream = _dbRef.child('users/${widget.user.uid}/history').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final Map<dynamic, dynamic> raw = event.snapshot.value as Map;
        final List<Map<String, dynamic>> temp = [];
        raw.forEach((key, value) {
          temp.add(Map<String, dynamic>.from(value as Map));
        });
        // Urutkan berdasarkan waktu mulai terbaru
        temp.sort((a, b) => (b['startTime'] ?? '').compareTo(a['startTime'] ?? ''));
        if (mounted) {
          setState(() {
            _myHistory = temp;
          });
        }
      }
    });
  }

  void _munculkanPeringatanKomando(String pesan, String komandan, String waktu) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF18181B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Colors.redAccent, width: 2),
          ),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 30),
              SizedBox(width: 10),
              Text("INSTRUKSI KOMANDO",
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"$pesan"', style: const TextStyle(fontSize: 14, color: Colors.white)),
              const SizedBox(height: 12),
              Text('Oleh: $komandan', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text('Waktu: $waktu', style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('SIAP LAKSANAKAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _checkAndRequestBackgroundLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) {
      return true;
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    if (!mounted) return false;

    // Tampilkan dialog penjelasan sebelum memicu prompt OS untuk background permission (Selalu Izinkan)
    final bool? setuju = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        title: Row(
          children: [
            const Icon(Icons.security_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'IZIN LOKASI "SELALU IZINKAN"',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agar pelacakan posisi tugas Anda tidak terputus saat layar HP mati atau ponsel terkunci, Anda sangat disarankan mengatur izin lokasi aplikasi ke "Selalu Izinkan" (Allow all the time).',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'Langkah Pengaturan Setelah Ini:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '1. Klik "ATUR SEKARANG" di bawah.\n2. Pilih menu "Izin" (Permissions) -> "Lokasi" (Location).\n3. Pilih opsi "Selalu Izinkan" (Allow all the time).',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nanti Saja', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D6EFD),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ATUR SEKARANG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (setuju == true) {
      LocationPermission newPermission = await Geolocator.requestPermission();
      if (newPermission == LocationPermission.always) {
        return true;
      }
      // Buka pengaturan aplikasi sebagai fallback
      await Geolocator.openAppSettings();
      newPermission = await Geolocator.checkPermission();
      return newPermission == LocationPermission.always;
    }
    return false;
  }

  void _fetchLocationPeriodic() {
    _fallbackLocationTimer?.cancel();
    _fallbackLocationTimer = Timer.periodic(const Duration(seconds: 8), (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
        if (mounted) {
          setState(() {
            _posisiSekarang = position;
          });
          _kirimLokasiKeFirebase(position);
        }
      } catch (e) {
        debugPrint('Periodic fallback location fetch failed: $e');
      }
    });
  }

  Future<void> _aktifkanTrackingSatelit() async {
    try {
      // Minta izin notifikasi untuk Android 13+ agar notification bar muncul
      if (Platform.isAndroid) {
        try {
          var status = await Permission.notification.status;
          if (status.isDenied) {
            status = await Permission.notification.request();
          }
          if (status.isPermanentlyDenied) {
            if (mounted) {
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  title: Text(
                    'Izin Notifikasi Diperlukan',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Text(
                    'Aplikasi memerlukan izin notifikasi agar status pelacakan (notification bar) dapat terus muncul saat tugas sedang berjalan.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D6EFD)),
                      onPressed: () async {
                        Navigator.pop(context);
                        await Geolocator.openAppSettings();
                      },
                      child: const Text('Buka Pengaturan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('Error requesting notification permission: $e');
        }
      }

      // Minta izin mengabaikan optimasi baterai agar tidak mati saat di-clear
      if (Platform.isAndroid) {
        try {
          final isOptimizing = await Permission.ignoreBatteryOptimizations.isDenied;
          if (isOptimizing) {
            if (mounted) {
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  title: Text(
                    'Pelacakan Latar Belakang',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Text(
                    'Agar pelacakan tetap berjalan lancar dan notifikasi tidak hilang saat aplikasi ditutup (clear dari recents), silakan lakukan langkah berikut:\n\n'
                    '1. Pilih opsi "Tidak ada pembatasan" (No restrictions / Unrestricted) pada halaman Detail Baterai setelah ini (JANGAN pilih "Penghemat baterai (rekomendasi)").\n'
                    '2. Sangat disarankan untuk mengaktifkan "Mulai otomatis" (Auto-start) pada pengaturan aplikasi.\n'
                    '3. Kunci aplikasi SIAGA di recents screen (tekan lama aplikasi di task manager, lalu pilih ikon Gembok).',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Lanjut', style: TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }
            await Permission.ignoreBatteryOptimizations.request();
          }
        } catch (e) {
          debugPrint('Error requesting battery optimization ignore: $e');
        }
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            title: Text(
              'GPS Tidak Aktif',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Pelacakan SIAGA memerlukan GPS aktif. Silakan buka Pengaturan untuk mengaktifkan GPS lokasi perangkat Anda.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D6EFD)),
                onPressed: () async {
                  Navigator.pop(context);
                  await Geolocator.openLocationSettings();
                },
                child: const Text('Pengaturan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Izin akses lokasi ditolak oleh Anda.', Colors.red);
          return;
        }
      }

      if (!mounted) return;
      if (permission == LocationPermission.deniedForever) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            title: Text(
              'Izin Lokasi Diblokir',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Izin lokasi SIAGA diblokir permanen. Silakan aktifkan izin lokasi manual di Pengaturan Aplikasi Anda.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D6EFD)),
                onPressed: () async {
                  Navigator.pop(context);
                  await Geolocator.openAppSettings();
                },
                child: const Text('Izin Aplikasi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        return;
      }

      // Meminta izin background lokasi "Selalu Izinkan"
      if (permission != LocationPermission.always) {
        await _checkAndRequestBackgroundLocation();
      }

      // --- WARM UP GPS ---
      Position? initialPos;
      try {
        initialPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
      } catch (e) {
        debugPrint('Warm up GPS failed: $e');
        try {
          initialPos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (initialPos != null && mounted) {
        setState(() {
          _posisiSekarang = initialPos;
        });
        _kirimLokasiKeFirebase(initialPos);
      }

      // Beri jeda kecil untuk kestabilan native service
      await Future.delayed(const Duration(milliseconds: 400));

      // Buka stream dengan retry jika transient error terjadi
      bool streamSuccess = false;
      int retryCount = 0;
      while (!streamSuccess && retryCount < 2) {
        try {
          final LocationSettings locationSettings;
          if (Platform.isAndroid) {
            locationSettings = AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 2,
              intervalDuration: const Duration(seconds: 5),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: "Pelacakan Taktis SIAGA",
                notificationText: "Aplikasi SIAGA memantau posisi patroli Anda di latar belakang.",
                notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
                enableWakeLock: true,
                setOngoing: true,
              ),
            );
          } else {
            locationSettings = const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 2,
            );
          }

          _positionStream = Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              if (mounted) {
                setState(() {
                  _posisiSekarang = position;
                });
                _kirimLokasiKeFirebase(position);
              }
            },
            onError: (error) {
              debugPrint('Stream error: $error');
              _fetchLocationPeriodic();
            },
          );
          streamSuccess = true;
        } catch (e) {
          retryCount++;
          debugPrint('Geolocator stream catch retry $retryCount: $e');
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (!streamSuccess) {
        debugPrint('getPositionStream failed. Using periodic fallback...');
        _fetchLocationPeriodic();
        _showSnackBar('Pelacakan diaktifkan (Mode Interval).', Colors.green);
      } else {
        _showSnackBar('Pelacakan tugas diaktifkan!', Colors.green);
      }

      if (_missionStartTime == null) {
        _missionStartTime = DateTime.now();
        _elapsedSeconds = 0;
      }
      _sessionTrackingPositions.clear();
      _sessionDistanceTraveled = 0.0;

      _missionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _elapsedSeconds = DateTime.now().difference(_missionStartTime ?? DateTime.now()).inSeconds;
            if (_elapsedSeconds < 0) _elapsedSeconds = 0;
          });
        }
      });

      setState(() {
        _isTracking = true;
        _homeState = HomeMissionState.active;
      });

      await _simpanStateTrackingKePrefs();
      _showSnackBar('Pelacakan tugas diaktifkan!', Colors.green);
    } catch (e) {
      debugPrint('Geolocator exception: $e');
      _showSnackBar('Gagal mengaktifkan GPS: Periksa izin lokasi atau aktifkan GPS Anda.', Colors.red);
      setState(() {
        _isTracking = false;
        _homeState = HomeMissionState.standby;
      });
      _missionTimer?.cancel();
      _positionStream?.cancel();
      _fallbackLocationTimer?.cancel();
      final String unitId = 'POL-$_nrp';
      _dbRef.child('live_tracking/$unitId').remove();
    }
  }

  void _kirimLokasiKeFirebase(Position pos) {
    if (!_isTracking) return;
    final String unitId = 'POL-$_nrp';
    final ref = _dbRef.child('live_tracking/$unitId');
    ref.onDisconnect().remove();
    
    // Tambahkan titik koordinat ke sesi dan hitung jarak tempuh (Task 41)
    if (_isTracking) {
      if (_sessionTrackingPositions.isNotEmpty) {
        final Position lastPos = _sessionTrackingPositions.last;
        final double distance = Geolocator.distanceBetween(
          lastPos.latitude,
          lastPos.longitude,
          pos.latitude,
          pos.longitude,
        );
        // Minimal perpindahan 1.5 meter untuk mengabaikan jitter GPS statis
        if (distance > 1.5) {
          _sessionDistanceTraveled += distance;
          _sessionTrackingPositions.add(pos);
        }
      } else {
        _sessionTrackingPositions.add(pos);
      }
    }
    
    // Throttle database writes based on _gpsInterval
    final DateTime now = DateTime.now();
    if (_lastFirebaseWriteTime != null) {
      final difference = now.difference(_lastFirebaseWriteTime!);
      if (difference.inSeconds < _gpsInterval) {
        return; // Skip Firebase write
      }
    }
    _lastFirebaseWriteTime = now;
    
    final String opCodeText = _opCodeController.text.trim();
    final String activityTypeText = _activityTypeController.text.trim();
    final String vehicleTypeText = _vehicleTypeController.text.trim();
    final String commanderText = _commanderController.text.trim();
    final String descriptionText = _descriptionController.text.trim();
    
    ref.set({
      'id_unit': unitId,
      'nama': _nama,
      'nrp': _nrp,
      'pangkat': _pangkat,
      'satker': _satker,
      'status': 'ACTIVE',
      'jenis_giat': activityTypeText.isNotEmpty ? activityTypeText : 'Pengamanan Wilayah',
      'jumlah_personel': int.tryParse(_personnelController.text) ?? 1,
      'op_code': opCodeText.isNotEmpty ? opCodeText : 'OPS-SIAGA-001',
      'commander': commanderText.isNotEmpty ? commanderText : 'Mandiri',
      'vehicle': vehicleTypeText.isNotEmpty ? vehicleTypeText : 'Mobil Dinas Roda 4',
      'description': descriptionText.isNotEmpty ? descriptionText : 'Pengamanan Kamtibmas',
      'no_hp': _noHpDinas,
      'koordinat': {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'akurasi': pos.accuracy
      },
      'waktu': DateTime.now().toIso8601String()
    }).catchError((err) {
      debugPrint('Database update error: $err');
    });
  }

  // Menyelesaikan Tugas
  Future<void> _selesaiTugasPatroli() async {
    final DateTime actualStartTime = _missionStartTime ?? DateTime.now();
    final int actualDurationSeconds = _elapsedSeconds;

    final String opCodeText = _opCodeController.text.trim();
    final String activityTypeText = _activityTypeController.text.trim();
    final String vehicleTypeText = _vehicleTypeController.text.trim();
    final String commanderText = _commanderController.text.trim();
    final String descriptionText = _descriptionController.text.trim();
    final int personnelCountVal = int.tryParse(_personnelController.text) ?? 1;

    setState(() {
      _isTracking = false;
      _homeState = HomeMissionState.standby;
      _missionStartTime = null;
      _elapsedSeconds = 0;
      // Bersihkan input setelah membaca nilainya
      _commanderController.clear();
      _descriptionController.clear();
      _personnelController.clear();
      _opCodeController.clear();
      _activityTypeController.clear();
      _vehicleTypeController.clear();
    });
    _missionTimer?.cancel();
    _positionStream?.cancel();
    _fallbackLocationTimer?.cancel();
    
    final String unitId = 'POL-$_nrp';
    
    // Simpan ke riwayat dan hapus state di background tanpa memblokir UI
    _dbRef.child('live_tracking/$unitId').remove().catchError((e) {
      debugPrint('Error removing live tracking: $e');
    });
    _hapusStateTrackingDariPrefs().catchError((e) {
      debugPrint('Error clearing tracking state: $e');
    });

    // Catat data misi ke tabel Riwayat Pengguna
    final DateTime endTime = DateTime.now();
    _dbRef.child('users/${widget.user.uid}/history').push().set({
      'opCode': opCodeText.isNotEmpty ? opCodeText : 'OPS-SIAGA-001',
      'activityType': activityTypeText.isNotEmpty ? activityTypeText : 'Pengamanan Wilayah',
      'vehicleType': vehicleTypeText.isNotEmpty ? vehicleTypeText : 'Mobil Dinas Roda 4',
      'commander': commanderText.isNotEmpty ? commanderText : 'Mandiri',
      'personnelCount': personnelCountVal,
      'description': descriptionText.isNotEmpty ? descriptionText : 'Pengamanan Kamtibmas',
      'startTime': actualStartTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'durationSeconds': actualDurationSeconds,
      'distance': _sessionDistanceTraveled,
      'pointsCount': _sessionTrackingPositions.length,
      'status': 'COMPLETED'
    }).catchError((err) {
      debugPrint('Error writing history: $err');
    });

    _showSnackBar('Laporan tugas selesai disimpan ke riwayat.', Colors.blue);
  }



  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Keluar dari SIAGA?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: const Text('Pelacakan GPS aktif akan dimatikan otomatis ketika Anda logout.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );

    if (confirm == true) {
      if (_isTracking) {
        final String unitId = 'POL-$_nrp';
        await _dbRef.child('live_tracking/$unitId').remove();
        await _hapusStateTrackingDariPrefs();
      }
      _missionTimer?.cancel();
      _positionStream?.cancel();
      _fallbackLocationTimer?.cancel();
      setState(() {
        _missionStartTime = null;
        _elapsedSeconds = 0;
      });
      await FirebaseAuth.instance.signOut();
    }
  }

  String _formatDuration(int seconds) {
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _fallbackLocationTimer?.cancel();
    _pesanStream?.cancel();
    _missionTimer?.cancel();
    _historyStream?.cancel();
    _dmSubscription?.cancel();
    _umumChatSubscription?.cancel();
    _geofencesSubscription?.cancel();
    _settingsSubscription?.cancel();
    _userSubscription?.cancel();
    _batterySubscription?.cancel();
    _gpsStatusSubscription?.cancel();
    _connectionSubscription?.cancel();
    _radarAnimationController.dispose();
    _commanderController.dispose();
    _personnelController.dispose();
    _descriptionController.dispose();
    _opCodeController.dispose();
    _activityTypeController.dispose();
    _vehicleTypeController.dispose();
    _customVehicleController.dispose();
    _chatMsgController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Widget _buildBlockScreen() {
    if (_maintenanceMode) {
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: () async {
            await _checkStatusDanInisialisasi();
          },
          color: const Color(0xFF0D6EFD),
          child: GridBackground(
            imageOpacity: 0.55,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.construction, size: 90, color: Colors.amber),
                      const SizedBox(height: 20),
                      const Text('PEMELIHARAAN SISTEM',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.amber)),
                      const SizedBox(height: 10),
                      const Text(
                        'Layanan pelacakan unit lapangan sedang dinonaktifkan sementara untuk pemeliharaan sistem. Silakan hubungi Posko Command Center jika darurat.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[850],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('Keluar Aplikasi'),
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkStatusDanInisialisasi();
        },
        color: const Color(0xFF0D6EFD),
        child: GridBackground(
          imageOpacity: 0.55,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_person_outlined, size: 90, color: Colors.orangeAccent),
                  const SizedBox(height: 20),
                  const Text('AKSES SISTEM TERTUNDA',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.orangeAccent)),
                  const SizedBox(height: 10),
                  const Text(
                    'Akun pendaftaran Anda saat ini berstatus PENDING dan sedang menunggu verifikasi validasi dari Administrator Posko Utama SIAGA.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 30),
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DETAIL PENDAFTARAN:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                        const SizedBox(height: 8),
                        Text('Nama: $_pangkat $_nama', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('NRP: $_nrp', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('Satker: $_satker', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        const Divider(color: Colors.grey),
                        Row(
                          children: const [
                            Icon(Icons.hourglass_empty, size: 14, color: Colors.orange),
                            SizedBox(width: 5),
                            Text('Status: MENUNGGU PERSETUJUAN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      label: const Text('KEMBALI KE LOGIN', style: TextStyle(color: Colors.white)),
                      onPressed: () => FirebaseAuth.instance.signOut(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  // Sub-Halaman Home: Standby (Image 1)
  Widget _buildHomeStandby() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Operator Active
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('OPERATOR AKTIF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text(
                        '$_pangkat $_nama',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text('NRP : $_nrp', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E3545),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _satker.toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Status SIAP BERTUGAS Card (Redesigned with pulsing wave indicator, SOS removed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                const RadarPingWaveWidget(),
                const SizedBox(height: 12),
                Text(
                  'SISTEM SIAP BERTUGAS',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface, letterSpacing: 1.0),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Aplikasi terhubung ke Posko Induk Bid TIK Polda Kalsel. Menunggu instruksi operasi lapangan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.shield_rounded, color: Colors.greenAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'KONEKSI TERENKRIPSI & TERLINDUNGI',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          const Text('STATUS SISTEM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5)),
          const SizedBox(height: 6),

          // 4 Grid Status (Dynamic state indicators)
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _buildStatusCard(
                  _gpsEnabled ? Icons.satellite_alt_rounded : Icons.gps_off_rounded,
                  'GPS',
                  _gpsEnabled ? 'Aktif' : 'Tidak Aktif',
                  valueColor: _gpsEnabled ? Colors.greenAccent : Colors.redAccent,
                ),
                _buildStatusCard(
                  _internetConnected ? Icons.cell_tower_rounded : Icons.signal_wifi_off_rounded,
                  'Internet',
                  _internetConnected ? 'Online' : 'Offline',
                  valueColor: _internetConnected ? Colors.greenAccent : Colors.redAccent,
                ),
                _buildStatusCard(
                  Icons.my_location_rounded,
                  'Pelacakan',
                  _isTracking ? 'Aktif' : 'Siaga',
                  valueColor: _isTracking ? Colors.blueAccent : Colors.grey,
                ),
                _buildStatusCard(
                  _isCharging
                      ? Icons.battery_charging_full_rounded
                      : (_batteryLevel < 20
                          ? Icons.battery_alert_rounded
                          : Icons.battery_full_rounded),
                  'Baterai',
                  '$_batteryLevel%',
                  valueColor: _isCharging
                      ? Colors.greenAccent
                      : (_batteryLevel < 20 ? Colors.redAccent : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                ),
              ],
            ),
          ),

          // Button Mulai Tugas
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8CE615), // Bright lime/green
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: const Text(
                'MULAI TUGAS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              onPressed: () {
                setState(() {
                  _homeState = HomeMissionState.formData;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(IconData icon, String label, String value, {Color? valueColor}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: valueColor ?? (isDark ? Colors.white70 : Colors.black87), size: 20),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor ?? (isDark ? Colors.white : Colors.black),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Sub-Halaman Home: Form Data Pra-Operasi (Image 2)
  Widget _buildHomeForm() {
    if (_vehicleTypeController.text.isEmpty) {
      _vehicleTypeController.text = 'Jalan Kaki';
      _selectedVehicleCategory = 'Jalan Kaki';
      _customVehicleController.clear();
    } else {
      const allowed = ['Jalan Kaki', 'Sepeda Motor', 'Mobil', 'Truk', 'Bus'];
      if (!allowed.contains(_selectedVehicleCategory) && _selectedVehicleCategory != 'Lainnya') {
        final currentText = _vehicleTypeController.text;
        if (allowed.contains(currentText)) {
          _selectedVehicleCategory = currentText;
        } else {
          _selectedVehicleCategory = 'Lainnya';
          if (_customVehicleController.text.isEmpty) {
            _customVehicleController.text = currentText;
          }
        }
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          const TikPolriShieldLogo(size: 65),
          const SizedBox(height: 15),
          Text(
            'Data Operasi Lapangan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Text(
              'Lengkapi form pra-operasi di bawah ini sebelum mengaktifkan pelacakan unit di lapangan.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.black54, height: 1.4),
            ),
          ),
          const SizedBox(height: 25),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Operation Code
                const Text('Kode Operasi', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                TextField(
                  controller: _opCodeController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'CONTOH: OPS-SIAGA-001',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                  ),
                ),
                const SizedBox(height: 15),

                // Activity Type
                const Text('🏃 Jenis Kegiatan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                TextField(
                  controller: _activityTypeController,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'CONTOH: PENGAMANAN STADION DEMANG LEHMAN',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                  ),
                ),
                const SizedBox(height: 15),

                // Vehicle Type
                const Text('🚙 Jenis Kendaraan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedVehicleCategory,
                  dropdownColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF18181B) : Colors.white,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Jalan Kaki', child: Text('Jalan Kaki')),
                    DropdownMenuItem(value: 'Sepeda Motor', child: Text('Sepeda Motor')),
                    DropdownMenuItem(value: 'Mobil', child: Text('Mobil')),
                    DropdownMenuItem(value: 'Truk', child: Text('Truk')),
                    DropdownMenuItem(value: 'Bus', child: Text('Bus')),
                    DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya (Isi Sendiri)')),
                  ],
                  onChanged: (String? val) {
                    if (val != null) {
                      setState(() {
                        _selectedVehicleCategory = val;
                        if (val == 'Lainnya') {
                          _vehicleTypeController.text = _customVehicleController.text.trim().isNotEmpty
                              ? _customVehicleController.text.trim()
                              : 'Lainnya';
                        } else {
                          _vehicleTypeController.text = val;
                        }
                      });
                    }
                  },
                ),
                if (_selectedVehicleCategory == 'Lainnya') ...[
                  const SizedBox(height: 12),
                  const Text('📝 Nama / Jenis Kendaraan Lainnya', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _customVehicleController,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'CONTOH: HELIKOPTER, KAPAL POLAIR, MOBIL SOUND',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _vehicleTypeController.text = val.trim().isNotEmpty ? val.trim() : 'Lainnya';
                      });
                    },
                  ),
                ],
                const SizedBox(height: 15),

                // Commander Name
                const Text('👤 Nama Komandan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                TextField(
                  controller: _commanderController,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'CONTOH: IPTU BUDI',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                  ),
                ),
                const SizedBox(height: 15),

                // Personnel Count
                const Text('👥 Jumlah Personel', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _personnelController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'CONTOH: 1',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // Task Description
                const Text('📄 Deskripsi Tugas', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'CONTOH: PENGAMANAN AREA UTAMA',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                    contentPadding: const EdgeInsets.all(12),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                  ),
                ),
                const SizedBox(height: 25),

                // Button Aktifkan Tracking
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444), // Red/coral
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                    label: const Text(
                      'AKTIFKAN PELACAKAN',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _aktifkanTrackingSatelit,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _homeState = HomeMissionState.standby;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                    ),
                    child: const Text(
                      'BATAL / KEMBALI',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sistem akan memantau lokasi unit secara real-time.',
            style: TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Sub-Halaman Home: Active Mission (Image 3)
  Widget _buildHomeActive() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          // Row 1: Operasi Berjalan & Avatar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Operasi Berjalan status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'OPERASI BERJALAN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEF4444),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Right: Profile Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
                  image: const DecorationImage(
                    image: AssetImage('assets/mascot_presisi.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Row 2: Status Badges (GPS, LTE, ON) & Battery
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Horizontal Status Badges
              Row(
                children: [
                  _buildMiniStatusBadge(
                    _gpsEnabled ? Icons.satellite_alt_rounded : Icons.gps_off_rounded,
                    _gpsEnabled ? 'GPS Aktif' : 'GPS Tidak Aktif',
                    textColor: _gpsEnabled ? Colors.greenAccent : Colors.redAccent,
                    iconColor: _gpsEnabled ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildMiniStatusBadge(
                    _internetConnected ? Icons.cell_tower_rounded : Icons.signal_wifi_off_rounded,
                    _internetConnected ? 'Internet Aktif' : 'Internet Terputus',
                    textColor: _internetConnected ? Colors.greenAccent : Colors.redAccent,
                    iconColor: _internetConnected ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildMiniStatusBadge(
                    Icons.circle_notifications_outlined,
                    'Tracking Aktif',
                    textColor: Colors.blueAccent,
                    iconColor: Colors.blueAccent,
                  ),
                ],
              ),

              // Right: Battery Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF18181B) : const Color(0xFFE4E4E7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isCharging
                          ? Icons.battery_charging_full_rounded
                          : (_batteryLevel < 20
                              ? Icons.battery_alert_rounded
                              : Icons.battery_std_rounded),
                      color: _isCharging
                          ? Colors.greenAccent
                          : (_batteryLevel < 20
                              ? Colors.redAccent
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white70
                                  : Colors.black87)),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_batteryLevel%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _isCharging
                            ? Colors.greenAccent
                            : (_batteryLevel < 20
                                ? Colors.redAccent
                                : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black87)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          // TIMER RAKSASA
          Text(
            _formatDuration(_elapsedSeconds),
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'WAKTU OPERASI BERJALAN',
            style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),

          const Spacer(),

          // Box Detail Misi
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMissionCol('KODE OP', _opCodeController.text.contains('-') ? _opCodeController.text.split('-').last : _opCodeController.text),
                    Container(width: 1, height: 40, color: Theme.of(context).dividerColor),
                    _buildMissionCol('AKURASI', _posisiSekarang != null ? '± ${_posisiSekarang!.accuracy.toStringAsFixed(1)}m' : '± 2.4m'),
                    Container(width: 1, height: 40, color: Theme.of(context).dividerColor),
                    _buildMissionCol('FILTER', '10m AKTIF'),
                  ],
                ),
                const SizedBox(height: 20),

                // Encryption Banner
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.lock_outline, color: Colors.grey, size: 14),
                      SizedBox(width: 8),
                      Text(
                        'KONEKSI AMAN AKTIF',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Button Live Streaming
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444), // Live red
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.videocam_rounded, size: 20),
                    label: const Text(
                      '📡 MULAI LIVE KAMERA',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: () {
                      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      if (myUid.isEmpty) return;
                      
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => LiveStreamingScreen(
                            dbRef: _dbRef,
                            uid: myUid,
                            nama: _nama,
                            pangkat: _pangkat,
                            nrp: _nrp,
                            satker: _satker.isNotEmpty ? _satker : 'Bid TIK',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Button Selesai Tugas
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF990000), // Dark red
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    label: const Text(
                      'SELESAI TUGAS',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: _selesaiTugasPatroli,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildMiniStatusBadge(IconData icon, String label, {Color? textColor, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? Colors.grey, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: textColor ?? Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissionCol(String label, String val) {
    IconData iconData;
    if (label == 'KODE OP') {
      iconData = Icons.badge_outlined;
    } else if (label == 'AKURASI') {
      iconData = Icons.gps_fixed_rounded;
    } else {
      iconData = Icons.filter_alt_outlined;
    }

    return Column(
      children: [
        Icon(iconData, color: Colors.grey, size: 14),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ============================================================================
  // TAB MENU 2: TACTICAL SONAR RADAR MAP (Image 4)
  // ============================================================================
  Widget _buildMapsTab() {
    return TacticalMapTab(
      posisiSekarang: _posisiSekarang,
      geofences: _geofences,
      nrp: _nrp,
      dbRef: _dbRef,
      gpsEnabled: _gpsEnabled,
    );
  }

  // ============================================================================
  // TAB MENU 3: LOGBOOK / RIWAYAT OPERASI (Image 5)
  // ============================================================================
  Widget _buildHistoryTab() {
    // Gunakan hanya riwayat asli dari DB
    final List<Map<String, dynamic>> finalHistory = List.from(_myHistory);

    // Hitung total jam tugas (konversi detik ke jam)
    int totalSeconds = 0;
    for (var m in finalHistory) {
      totalSeconds += (m['durationSeconds'] as int? ?? 0);
    }
    final int totalHours = totalSeconds ~/ 3600;

    return RefreshIndicator(
      onRefresh: () async {
        await _checkStatusDanInisialisasi();
      },
      color: const Color(0xFF0D6EFD),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row Total Tugas & Operasi Selesai
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, 
                    borderRadius: BorderRadius.circular(10), 
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL JAM TUGAS', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Text('$totalHours HRS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, 
                    borderRadius: BorderRadius.circular(10), 
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('OPERASI SELESAI', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Text('${finalHistory.length} OPS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),

          Text('Riwayat Operasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 15),

          Expanded(
            child: finalHistory.isEmpty
                ? const SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          'Belum ada riwayat operasi.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: finalHistory.length,
              itemBuilder: (context, index) {
                final mission = finalHistory[index];
                final isIncident = mission['status'] == 'INCIDENT LOGGED';
                final DateTime start = DateTime.tryParse(mission['startTime'] ?? '') ?? DateTime.now();
                final DateTime end = DateTime.tryParse(mission['endTime'] ?? '') ?? DateTime.now();
                
                final int durationHrs = (mission['durationSeconds'] as int? ?? 0) ~/ 3600;
                final String timeText = '${start.hour.toString().padLeft(2, '0')}:00 - ${end.hour.toString().padLeft(2, '0')}:00 (${durationHrs}h)';

                final durationSeconds = mission['durationSeconds'] as int? ?? 0;
                final int hours = durationSeconds ~/ 3600;
                final int minutes = (durationSeconds % 3600) ~/ 60;
                final int seconds = durationSeconds % 60;
                final String durationText = hours > 0 
                    ? '$hours jam $minutes m' 
                    : (minutes > 0 ? '$minutes m $seconds s' : '$seconds s');

                final double distanceMeters = (mission['distance'] as num? ?? 0.0).toDouble();
                final String distanceText = distanceMeters >= 1000 
                    ? '${(distanceMeters / 1000).toStringAsFixed(1)} km' 
                    : '${distanceMeters.toStringAsFixed(0)} m';

                final int pointsCount = mission['pointsCount'] as int? ?? 0;
                final String pointsText = '$pointsCount titik';

                return Container(
                  padding: const EdgeInsets.all(15),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isIncident ? Colors.redAccent.withValues(alpha: 0.4) : Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E3545),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              mission['opCode'] ?? 'OP-99',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.circle, color: isIncident ? Colors.red : Colors.green, size: 6),
                          const SizedBox(width: 4),
                          Text(
                            isIncident ? 'INSIDEN TERCATAT' : 'SELESAI',
                            style: TextStyle(
                              fontSize: 9, 
                              fontWeight: FontWeight.bold, 
                              color: isIncident ? Colors.redAccent : Colors.greenAccent
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        mission['activityType'] ?? 'Pengamanan Wilayah',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            '${start.day} ${_getMonthName(start.month)} ${start.year}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(width: 15),
                          const Icon(Icons.access_time, size: 12, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            timeText,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 12, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            durationText,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(width: 15),
                          const Icon(Icons.map_outlined, size: 12, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            distanceText,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(width: 15),
                          const Icon(Icons.pin_drop_outlined, size: 12, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            pointsText,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 90,
                        height: 30,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Theme.of(context).dividerColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () => _showMissionDetailsDialog(mission),
                          child: Text(
                            'DETAIL',
                            style: TextStyle(
                              fontSize: 9, 
                              fontWeight: FontWeight.bold, 
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    ),
  );
}

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return names[month - 1];
    return 'Oct';
  }

  void _showMissionDetailsDialog(Map<String, dynamic> mission) {
    final int durationSeconds = mission['durationSeconds'] as int? ?? 0;
    final int hours = durationSeconds ~/ 3600;
    final int minutes = (durationSeconds % 3600) ~/ 60;
    final int seconds = durationSeconds % 60;
    final String durationText = hours > 0 
        ? '$hours jam $minutes menit' 
        : (minutes > 0 ? '$minutes menit $seconds detik' : '$seconds detik');

    final double distanceMeters = (mission['distance'] as num? ?? 0.0).toDouble();
    final String distanceText = distanceMeters >= 1000 
        ? '${(distanceMeters / 1000).toStringAsFixed(2)} km' 
        : '${distanceMeters.toStringAsFixed(0)} meter';

    final int pointsCount = mission['pointsCount'] as int? ?? 0;
    final String pointsText = '$pointsCount titik koordinat';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFF27272A))),
        title: Text(mission['opCode'] ?? 'Rincian Operasi', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jenis Giat: ${mission['activityType']}', style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 8),
            Text('Kendaraan: ${mission['vehicleType'] ?? 'Roda 2'}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Komandan Tim: ${mission['commander']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Kekuatan Personel: ${mission['personnelCount']} Anggota', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Durasi Tugas: $durationText', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Jarak Tempuh: $distanceText', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Titik Tracking: $pointsText', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF27272A)),
            const Text('Deskripsi Tugas:', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(mission['description'] ?? '-', style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3545)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // ============================================================================
  // TAB MENU 4: PROFILE SCREEN
  // ============================================================================
  Future<void> _pilihFotoProfil() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await showDialog<XFile?>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF18181B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFF27272A))),
          title: const Text('Ganti Foto Profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Colors.blueAccent),
                title: const Text('Pilih dari Galeri', style: TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () async {
                  final file = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 200,
                    maxHeight: 200,
                    imageQuality: 70,
                  );
                  if (context.mounted) Navigator.pop(context, file);
                },
              ),
              const Divider(color: Color(0xFF27272A)),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: Colors.blueAccent),
                title: const Text('Ambil dari Kamera', style: TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () async {
                  final file = await picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 200,
                    maxHeight: 200,
                    imageQuality: 70,
                  );
                  if (context.mounted) Navigator.pop(context, file);
                },
              ),
            ],
          ),
        ),
      );

      if (pickedFile != null) {
        final bytes = await File(pickedFile.path).readAsBytes();
        final base64String = base64Encode(bytes);
        
        // Simpan ke Firebase Database
        await _dbRef.child('users/${widget.user.uid}').update({
          'foto_profil': base64String
        });
        
        setState(() {
          _fotoProfil = base64String;
        });
        
        _showSnackBar('Foto profil berhasil diperbarui!', Colors.green);
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      _showSnackBar('Gagal memperbarui foto profil: $e', Colors.red);
    }
  }

  void _showEditNoHpDialog() {
    final controller = TextEditingController(text: _noHpDinas);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Theme.of(context).dividerColor)),
        title: Row(
          children: [
            Icon(Icons.phone_android, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            Text('Ubah Nomor HP Dinas', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan nomor HP Dinas / WhatsApp aktif Anda untuk koordinasi selama tugas.',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Contoh: 08123456789',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
            onPressed: () async {
              final val = controller.text.trim();
              if (val.isEmpty) {
                _showSnackBar('Nomor HP tidak boleh kosong', Colors.red);
                return;
              }
              Navigator.pop(context);
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await FirebaseDatabase.instance.ref()
                      .child('users')
                      .child(user.uid)
                      .update({
                    'no_hp_dinas': val
                  });
                  _showSnackBar('Nomor HP berhasil diperbarui!', Colors.green);
                }
              } catch (e) {
                _showSnackBar('Gagal memperbarui nomor HP: $e', Colors.red);
              }
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showAccountSecurityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Theme.of(context).dividerColor)),
        title: Row(
          children: [
            Icon(Icons.security, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            Text('Keamanan Akun', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSecurityInfoRow('Enkripsi Transmisi', 'AES-256 Aktif', Colors.green),
            const SizedBox(height: 10),
            _buildSecurityInfoRow('Koneksi Server', 'Terproteksi SSL', Colors.green),
            const SizedBox(height: 10),
            _buildSecurityInfoRow('Integritas Sinyal', 'Terverifikasi', Colors.green),
            const SizedBox(height: 15),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 5),
            const Text(
              'Untuk menjaga kerahasiaan operasi kepolisian, penggantian kata sandi wajib diajukan melalui unit TIK Polda Kalsel.',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3545)),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildSecurityInfoRow(String label, String value, Color statusColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Row(
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
          ],
        )
      ],
    );
  }

  void _showAppVersionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Theme.of(context).dividerColor)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            Text('Informasi Versi Aplikasi', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SIAGA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 4),
            const Text('Versi: 1.0.0', style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3545)),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Theme.of(context).dividerColor)),
        title: Row(
          children: [
            Icon(Icons.privacy_tip_outlined, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            Text('Kebijakan Privasi', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Aplikasi SIAGA mengumpulkan data lokasi latar belakang (background location) hanya pada saat Anda mengaktifkan tugas operasi di lapangan.\n\nData koordinat lokasi Anda dikirimkan secara aman ke Posko Induk Bid TIK Polda Kalsel guna kepentingan monitoring pergerakan unit, keselamatan personel, dan efisiensi koordinasi tugas.\n\nKami berkomitmen untuk menjaga kerahasiaan data lokasi Anda. Data tersebut tidak akan dibagikan kepada pihak ketiga mana pun di luar kepentingan kedinasan Kepolisian Negara Republik Indonesia.',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3545)),
            onPressed: () => Navigator.pop(context),
            child: const Text('SAYA MENGERTI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          )
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _checkStatusDanInisialisasi();
      },
      color: const Color(0xFF0D6EFD),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Operator Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                // Avatar Box Clickable to edit
                GestureDetector(
                  onTap: _pilihFotoProfil,
                  child: Stack(
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: _fotoProfil.isNotEmpty
                              ? Image.memory(
                                  base64Decode(_fotoProfil),
                                  fit: BoxFit.cover,
                                  width: 110,
                                  height: 110,
                                )
                              : Image.asset(
                                  'assets/mascot_presisi.png',
                                  fit: BoxFit.cover,
                                  width: 110,
                                  height: 110,
                                  errorBuilder: (ctx, err, st) => const Icon(Icons.person, size: 50, color: Colors.grey),
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit, color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                
                // Operator Name
                Text(
                  _nama.isNotEmpty ? _nama : 'Bripda Ahmad Fauzi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),
                
                // Badges NRP & Rank
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Text(
                        'NRP: ${_nrp.isNotEmpty ? _nrp : "12345"}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.black54,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Text(
                        'PANGKAT: ${_pangkat.isNotEmpty ? _pangkat : "BRIPDA"}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.black54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Text(
                        'PERAN: ${_getRoleDisplayName(_role)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.black54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. UNIT DATA Card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unit Data Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF242427) : const Color(0xFFE4E4E7),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                  ),
                  child: const Text(
                    'DATA UNIT',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0),
                  ),
                ),
                
                // Designation row
                _buildUnitItem(
                  Icons.shield_outlined,
                  'JABATAN',
                  _jabatan.isNotEmpty ? _jabatan : 'Sabhara',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15.0),
                  child: Divider(color: Theme.of(context).dividerColor, height: 1),
                ),
                
                // Posko Induk TIK row
                _buildUnitItem(
                  Icons.location_on_outlined,
                  'POSKO INDUK TIK',
                  _satker.isNotEmpty ? _satker : 'Polda Kalimantan Selatan',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15.0),
                  child: Divider(color: Theme.of(context).dividerColor, height: 1),
                ),
                
                // Nomor HP Dinas row
                _buildEditableUnitItem(
                  Icons.phone_android_outlined,
                  'NOMOR HP DINAS',
                  _noHpDinas.isNotEmpty ? _noHpDinas : 'Belum diatur (Ketuk untuk ubah)',
                  onTap: _showEditNoHpDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Actions / Security Cards list
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                _buildActionRow(
                  Icons.lock_outline_rounded,
                  'Keamanan Akun',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                  onTap: _showAccountSecurityDialog,
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                _buildActionRow(
                  Icons.info_outline_rounded,
                  'Versi Aplikasi',
                  trailing: const Text('1.0.0', style: TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'monospace')),
                  onTap: _showAppVersionDialog,
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                _buildActionRow(
                  Icons.verified_user_outlined,
                  'Kebijakan Privasi',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                  onTap: _showPrivacyPolicyDialog,
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                
                // Theme Switcher Row (Task 8 Toggle Theme)
                _buildActionRow(
                  Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  Theme.of(context).brightness == Brightness.dark ? 'Tema Terang' : 'Tema Gelap',
                  trailing: Icon(
                    Theme.of(context).brightness == Brightness.dark ? Icons.wb_sunny_rounded : Icons.nightlight_round_rounded,
                    color: Colors.amber,
                    size: 18,
                  ),
                  onTap: () async {
                    final nextMode = Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
                    themeNotifier.value = nextMode;
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('theme_mode', nextMode == ThemeMode.light ? 'light' : 'dark');
                    } catch (e) {
                      debugPrint('Error saving theme: $e');
                    }
                  },
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                
                _buildActionRow(
                  Icons.logout_rounded,
                  'Keluar Akun',
                  textColor: const Color(0xFFF87171), // Red/salmon colored
                  iconColor: const Color(0xFFF87171),
                  onTap: _logout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

  Widget _buildEditableUnitItem(IconData icon, String title, String value, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF242427) : const Color(0xFFF1F1F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.grey, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: value.contains('Belum diatur') ? Colors.redAccent : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit, color: Theme.of(context).primaryColor, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitItem(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.all(15.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF242427) : const Color(0xFFF1F1F4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.grey, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    IconData icon,
    String title, {
    Widget? trailing,
    Color? textColor,
    Color iconColor = Colors.grey,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap ?? () {},
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 15),
            Text(title, style: TextStyle(fontSize: 14, color: textColor ?? Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // LIVE CHAT TAB — Two-level: list + conversation
  // ============================================================================
  Widget _buildChatTab() {
    if (_chatLevel == 'conversation') {
      return _buildChatConversation();
    }
    return _buildChatList();
  }

  /// Level 1: Chat list — Umum + DM contacts
  Widget _buildChatList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF18181B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return RefreshIndicator(
      onRefresh: () async {
        await _checkStatusDanInisialisasi();
      },
      color: const Color(0xFF0D6EFD),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: cardColor,
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981), shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'PESAN',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),

          // Siaran Umum button
          InkWell(
            onTap: () {
              setState(() {
                _chatLevel = 'conversation';
                _chatPath = 'chat/umum';
                _dmConvId = '';
                _dmTargetName = 'Siaran Umum';
                _anyUnreadPublic = false;
                _lastReadUmum = DateTime.now().millisecondsSinceEpoch;
              });
              SharedPreferences.getInstance().then((prefs) {
                prefs.setInt('umum_last_read', _lastReadUmum);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.tag, color: Color(0xFF3B82F6), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Siaran Umum', style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        )),
                        const SizedBox(height: 2),
                        Text('Semua personel', style: TextStyle(
                          fontSize: 12, color: Colors.grey[500],
                        )),
                      ],
                    ),
                  ),
                  if (_anyUnreadPublic)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '1',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                ],
              ),
            ),
          ),

          // DM contacts section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('PESAN PRIBADI', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 1.2, color: Colors.grey[500],
              )),
            ),
          ),

          // Contact list from Firebase
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance.ref('chat/dm').onValue,
              builder: (context, dmSnapshot) {
                final dmConversations = <String, Map<String, dynamic>>{};
                if (dmSnapshot.hasData && dmSnapshot.data?.snapshot.value != null) {
                  try {
                    final rawDm = Map<String, dynamic>.from(dmSnapshot.data!.snapshot.value as Map);
                    rawDm.forEach((convId, data) {
                      if (data is Map) {
                        dmConversations[convId] = Map<String, dynamic>.from(data);
                      }
                    });
                  } catch (_) {}
                }

                return StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref('users').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          height: 250,
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 40, color: Colors.orange[400]),
                                const SizedBox(height: 8),
                                Text('Gagal memuat kontak', style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(snapshot.error.toString(), style: TextStyle(color: Colors.grey[500], fontSize: 10), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final raw = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
                    final contacts = <Map<String, dynamic>>[];
                    raw.forEach((uid, val) {
                      if (uid == myUid) return;
                      if (val is! Map) return;
                      final u = Map<String, dynamic>.from(val);
                      if (u['status'] != 'active') return;
                      // Members only see admin/commander
                      if (_role == 'member' && u['role'] != 'admin' && u['role'] != 'commander') return;
                      contacts.add({'uid': uid, ...u});
                    });
                    contacts.sort((a, b) => (a['nama'] ?? '').compareTo(b['nama'] ?? ''));

                    if (contacts.isEmpty) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          height: 250,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 40, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text('Belum ada kontak tersedia', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: contacts.length,
                      itemBuilder: (ctx, i) {
                        final c = contacts[i];
                        final fullName = '${c['pangkat'] ?? ''} ${c['nama'] ?? '?'}'.trim();
                        final initial = ((c['nama'] ?? '?') as String).isNotEmpty
                            ? (c['nama'] as String)[0].toUpperCase() : '?';

                        // Check unread status for this contact
                        String? convId;
                        Map<String, dynamic>? conversationData;
                        dmConversations.forEach((key, value) {
                          final participants = value['participants'] as Map?;
                          if (participants != null &&
                              participants[myUid] == true &&
                              participants[c['uid']] == true) {
                            convId = key;
                            conversationData = value;
                          }
                        });

                        bool hasUnread = false;
                        if (convId != null && conversationData != null) {
                          final lastSender = conversationData!['lastSender'];
                          final isFromOther = lastSender == null || lastSender != myUid;
                          if (isFromOther) {
                            final lastRead = _lastReadMap[convId] ?? 0;
                            final updatedAt = conversationData!['updatedAt'] ?? 0;
                            if (updatedAt > lastRead) {
                              hasUnread = true;
                            }
                          }
                        }

                        return InkWell(
                          onTap: () => _openDmChat(c['uid'], fullName),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.5))),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  child: Text(initial, style: const TextStyle(
                                    color: Color(0xFF3B82F6), fontSize: 14, fontWeight: FontWeight.bold,
                                  )),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(fullName, style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                      )),
                                      const SizedBox(height: 2),
                                      Text(_getRoleDisplayName(c['role']?.toString()), style: TextStyle(
                                        fontSize: 11, color: Colors.grey[500],
                                      )),
                                    ],
                                  ),
                                ),
                                if (hasUnread)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '1',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Open or find existing DM conversation with target user
  Future<void> _openDmChat(String targetUid, String targetName) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    String? convId;

    // Check if conversation already exists
    final dmSnap = await FirebaseDatabase.instance.ref('chat/dm').get();
    if (dmSnap.exists) {
      final dmData = Map<String, dynamic>.from(dmSnap.value as Map);
      for (final entry in dmData.entries) {
        final conv = Map<String, dynamic>.from(entry.value as Map);
        final participants = conv['participants'] as Map?;
        if (participants != null &&
            participants[myUid] == true &&
            participants[targetUid] == true) {
          convId = entry.key;
          break;
        }
      }
    }

    // If no conversation and user is not admin/commander, block
    if (convId == null && _role != 'admin' && _role != 'commander') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya Komandan dan Admin yang dapat memulai pesan pribadi'),
          duration: Duration(milliseconds: 1000),
        ),
      );
      return;
    }

    // Create new conversation if needed
    if (convId == null) {
      final newRef = FirebaseDatabase.instance.ref('chat/dm').push();
      convId = newRef.key;
      await newRef.set({
        'participants': {myUid: true, targetUid: true},
        'lastMessage': '',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('dm_last_read_$convId', now);
    
    setState(() {
      _lastReadMap[convId!] = now;
      _chatLevel = 'conversation';
      _chatPath = 'chat/dm/$convId/messages';
      _dmConvId = convId;
      _dmTargetName = targetName;
    });
    _updateAnyUnreadDms(_latestDmData);
  }

  void _confirmDeleteMessage(String msgKey, String chatPath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF18181B)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus Pesan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('Apakah Anda yakin ingin menghapus pesan ini secara permanen?', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('BATAL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              FirebaseDatabase.instance.ref('$chatPath/$msgKey').remove().then((_) {
                _showSnackBar('Pesan berhasil dihapus.', Colors.green);
              }).catchError((err) {
                _showSnackBar('Gagal menghapus pesan: $err', Colors.red);
              });
            },
            child: const Text('HAPUS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Level 2: Chat conversation view
  Widget _buildChatConversation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF09090B) : const Color(0xFFF4F4F5);
    final cardColor = isDark ? const Color(0xFF18181B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final msgController = _chatMsgController;
    final scrollController = _chatScrollController;
    final chatPath = _chatPath;
    final dmConvId = _dmConvId;

    void sendMsg() {
      final text = msgController.text.trim();
      if (text.isEmpty) return;
      msgController.clear();
      FirebaseDatabase.instance.ref(chatPath).push().set({
        'uid': myUid,
        'nrp': _nrp,
        'nama': _nama,
        'pangkat': _pangkat,
        'pesan': text,
        'waktu': DateTime.now().toIso8601String(),
      }).then((_) {
        // Update DM metadata
        if (dmConvId.isNotEmpty) {
          FirebaseDatabase.instance.ref('chat/dm/$dmConvId').update({
            'lastMessage': text.length > 80 ? text.substring(0, 80) : text,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            'lastSender': myUid,
          });
        }
      });
    }

    return Column(
      children: [
        // Header with back button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: cardColor,
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _chatLevel = 'list';
                    _dmConvId = '';
                  });
                  _updateAnyUnreadDms(_latestDmData);
                },
                child: Icon(Icons.arrow_back_ios, size: 18, color: isDark ? Colors.white : Colors.black87),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981), shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dmTargetName,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                dmConvId.isEmpty ? Icons.tag : Icons.person,
                size: 18, color: Colors.grey[500],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: borderColor),

        // Pesan area
        Expanded(
          child: StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref(chatPath).onValue,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 52, color: Colors.grey[700]),
                      const SizedBox(height: 12),
                      Text('Belum ada pesan', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      Text('Jadilah yang pertama!', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    ],
                  ),
                );
              }

              final raw = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
              final msgs = raw.entries.map((e) {
                final m = Map<String, dynamic>.from(e.value as Map);
                m['_key'] = e.key;
                return m;
              }).toList()
                ..sort((a, b) => (a['_key'] ?? '').compareTo(b['_key'] ?? ''));

              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (dmConvId.isNotEmpty && msgs.isNotEmpty) {
                  final latestMsg = msgs.last;
                  final latestTimeStr = latestMsg['waktu'] ?? '';
                  int latestTimestamp = 0;
                  try {
                    latestTimestamp = DateTime.parse(latestTimeStr).millisecondsSinceEpoch;
                  } catch (e) {
                    latestTimestamp = DateTime.now().millisecondsSinceEpoch;
                  }

                  final currentLastRead = _lastReadMap[dmConvId] ?? 0;
                  if (latestTimestamp > currentLastRead) {
                    final prefs = await SharedPreferences.getInstance();
                    final now = DateTime.now().millisecondsSinceEpoch;
                    await prefs.setInt('dm_last_read_$dmConvId', now);
                    setState(() {
                      _lastReadMap[dmConvId] = now;
                    });
                    _updateAnyUnreadDms(_latestDmData);
                  }
                }
                if (scrollController.hasClients) {
                  scrollController.animateTo(
                    scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              });

              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                itemCount: msgs.length,
                itemBuilder: (ctx, i) {
                  final msg = msgs[i];
                  final isMe = msg['uid'] == myUid;
                  final nama = '${msg['pangkat'] ?? ''} ${msg['nama'] ?? '?'}'.trim();
                  final inisial = ((msg['nama'] ?? '?') as String).isNotEmpty
                      ? (msg['nama'] as String)[0].toUpperCase()
                      : '?';
                  String waktu = '';
                  if (msg['waktu'] != null) {
                    try {
                      final dt = DateTime.parse(msg['waktu']).toLocal();
                      waktu = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
                    } catch (_) {}
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe) ...[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                            child: Text(inisial, style: const TextStyle(
                              color: Color(0xFF3B82F6), fontSize: 12, fontWeight: FontWeight.bold,
                            )),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (isMe) const Spacer(),
                        Flexible(
                          flex: 0,
                          child: GestureDetector(
                            onLongPress: () {
                              if (isMe || _role == 'admin') {
                                _confirmDeleteMessage(msg['_key'] ?? '', chatPath);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF1D4ED8) : cardColor,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft: isMe ? const Radius.circular(14) : const Radius.circular(3),
                                bottomRight: isMe ? const Radius.circular(3) : const Radius.circular(14),
                              ),
                              border: isMe ? null : Border.all(color: borderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      nama,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF3B82F6)),
                                    ),
                                  ),
                                Text(
                                  msg['pesan'] ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Text(waktu, style: TextStyle(fontSize: 9, color: isMe ? Colors.white70 : Colors.grey[500])),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                        if (!isMe) const Spacer(),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor),
                    ),
                    child: TextField(
                      controller: msgController,
                      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Ketik pesan...',
                        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      ),
                      onSubmitted: (_) => sendMsg(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: sendMsg,
                  child: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  @override
  Widget build(BuildContext context) {
    if (_checkingStatus) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0D6EFD))),
      );
    }

    if (_status != 'active' || _maintenanceMode) {
      return _buildBlockScreen();
    }

    // 1. Pilih Widget Konten Berdasarkan Tab Menu Utama
    Widget bodyContent;
    String appBarTitle;
    
    switch (_currentIndex) {
      case 0:
        appBarTitle = 'SIAGA';
        if (_homeState == HomeMissionState.formData) {
          bodyContent = _buildHomeForm();
        } else if (_homeState == HomeMissionState.active) {
          bodyContent = _buildHomeActive();
        } else {
          bodyContent = RefreshIndicator(
            onRefresh: () async {
              await _checkStatusDanInisialisasi();
            },
            color: const Color(0xFF0D6EFD),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom -
                    kToolbarHeight -
                    kBottomNavigationBarHeight -
                    20,
                child: _buildHomeStandby(),
              ),
            ),
          );
        }
        break;
      case 1:
        appBarTitle = 'KOMUNIKASI';
        bodyContent = _buildChatTab();
        break;
      case 2:
        appBarTitle = 'SIAGA MAPS';
        bodyContent = _buildMapsTab();
        break;
      case 3:
        appBarTitle = 'SIAGA';
        bodyContent = _buildHistoryTab();
        break;
      case 4:
        appBarTitle = 'PROFIL SAYA';
        bodyContent = _buildProfileTab();
        break;
      default:
        appBarTitle = 'SIAGA';
        bodyContent = _buildHomeStandby();
    }

    // 2. Jika Sedang Transmisi Aktif dan berada di menu Home, Kita sembunyikan default AppBar 
    // agar visualisasi Timer/Operasi Berjalan menyatu penuh ke layar.
    final bool hideDefaultAppBar = (_currentIndex == 0 && _homeState == HomeMissionState.active);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        // Case 1: If in chat conversation, go back to chat list
        if (_currentIndex == 1 && _chatLevel == 'conversation') {
          setState(() {
            _chatLevel = 'list';
            _dmConvId = '';
          });
          _updateAnyUnreadDms(_latestDmData);
          return;
        }
        
        // Case 2: If not on Beranda tab (index 0), switch to Beranda tab
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
          return;
        }
        
        // Case 3: If on Beranda, but in active mission / tracking
        if (_isTracking) {
          try {
            const platform = MethodChannel('com.example.siaga_tracker/app');
            await platform.invokeMethod('minimizeApp');
          } catch (e) {
            debugPrint('Error minimizing app: $e');
          }
          return;
        }
        
        // Case 4: Default - exit app
        SystemNavigator.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: _currentIndex != 2,
        appBar: hideDefaultAppBar
            ? null
            : AppBar(
                title: Row(
                  children: [
                    const TikPolriShieldLogo(size: 20),
                    const SizedBox(width: 8),
                    Text(appBarTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  ],
                ),
                centerTitle: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.sensors, color: Colors.greenAccent, size: 20),
                    onPressed: () {},
                  )
                ],
              ),
        body: GridBackground(
          child: bodyContent,
        ),
        bottomNavigationBar: CustomBottomNavBar(
          currentIndex: _currentIndex,
          hasUnread: _anyUnreadDms || _anyUnreadPublic,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }
}

// Custom Bottom Navigation Bar matching Screenshot pill highlight style
class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final bool hasUnread;
  final Function(int) onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    this.hasUnread = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      _NavBarItem(icon: Icons.grid_view_rounded, label: 'Beranda'),
      _NavBarItem(icon: Icons.chat_bubble_outline_rounded, label: 'Chat'),
      _NavBarItem(icon: Icons.map_outlined, label: 'Peta'),
      _NavBarItem(icon: Icons.history_rounded, label: 'Riwayat'),
      _NavBarItem(icon: Icons.person_outline_rounded, label: 'Profil'),
    ];

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isSelected = currentIndex == index;
          return InkWell(
            onTap: () => onTap(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: isSelected
                  ? BoxDecoration(
                      color: isDark 
                          ? const Color(0xFF2E3545).withValues(alpha: 0.4)
                          : const Color(0xFF3B82F6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        items[index].icon,
                        color: isSelected 
                            ? (isDark ? Colors.white : Theme.of(context).primaryColor)
                            : Colors.grey,
                        size: 24,
                      ),
                      if (items[index].label == 'Chat' && hasUnread)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[index].label,
                    style: TextStyle(
                      color: isSelected 
                          ? (isDark ? Colors.white : Theme.of(context).primaryColor)
                          : Colors.grey,
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavBarItem {
  final IconData icon;
  final String label;
  _NavBarItem({required this.icon, required this.label});
}

// ============================================================================
// WIDGET DRAWING: TACTICAL RADAR SONAR PAINTER (Image 4)
// ============================================================================
class RadarRadarPainter extends CustomPainter {
  final double sweepAngle;
  RadarRadarPainter({required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paintGrid = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final paintGreenLine = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw concentric rings
    canvas.drawCircle(center, size.width * 0.45, paintGrid);
    canvas.drawCircle(center, size.width * 0.32, paintGrid);
    canvas.drawCircle(center, size.width * 0.18, paintGrid);

    // Draw grid crosshairs
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paintGrid);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paintGrid);

    // Draw radar sweep line rotating
    final double radius = size.width * 0.5;
    final double radian = (sweepAngle % 360) * 3.14159 / 180;
    final Offset sweepTarget = Offset(
      center.dx + radius * math.cos(radian),
      center.dy + radius * math.sin(radian),
    );
    canvas.drawLine(center, sweepTarget, paintGreenLine);

  }


  @override
  bool shouldRepaint(covariant RadarRadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle;
  }
}

class RadarPingWaveWidget extends StatelessWidget {
  const RadarPingWaveWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer ring (static)
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
        ),
        // Inner circle
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF10B981).withValues(alpha: 0.1),
            border: Border.all(
              color: const Color(0xFF10B981),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.wifi_tethering_rounded,
            color: Color(0xFF10B981),
            size: 20,
          ),
        ),
      ],
    );
  }
}

class TacticalMapTab extends StatefulWidget {
  final Position? posisiSekarang;
  final List<Map<String, dynamic>> geofences;
  final String nrp;
  final DatabaseReference dbRef;
  final bool gpsEnabled;

  const TacticalMapTab({
    super.key,
    required this.posisiSekarang,
    required this.geofences,
    required this.nrp,
    required this.dbRef,
    required this.gpsEnabled,
  });

  @override
  State<TacticalMapTab> createState() => _TacticalMapTabState();
}

class _TacticalMapTabState extends State<TacticalMapTab> {
  final MapController _mapController = MapController();
  String? _mapStyle;
  bool _isSearchingLocation = false;
  final TextEditingController _searchController = TextEditingController();
  int _mapRefreshKey = 0;
  late Stream<DatabaseEvent> _liveTrackingStream;

  @override
  void initState() {
    super.initState();
    _liveTrackingStream = widget.dbRef.child('live_tracking').onValue;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        backgroundColor: color,
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;

    final normalizedQuery = query.toLowerCase();
    LatLng? foundUnitLocation;
    Map<String, dynamic>? foundUnitData;

    try {
      final snapshot = await widget.dbRef.child('live_tracking').get();
      if (snapshot.exists && snapshot.value != null) {
        final Map<dynamic, dynamic> raw = snapshot.value as Map;
        for (var entry in raw.entries) {
          final u = Map<String, dynamic>.from(entry.value as Map);
          final name = (u['nama'] ?? '').toString().toLowerCase();
          final nrp = (u['nrp'] ?? '').toString();
          
          if (name.contains(normalizedQuery) || nrp.contains(normalizedQuery)) {
            final k = Map<String, dynamic>.from(u['koordinat'] ?? {});
            final double? lat = k['lat'] as double?;
            final double? lng = k['lng'] as double?;
            if (lat != null && lng != null) {
              foundUnitLocation = LatLng(lat, lng);
              foundUnitData = u;
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Local units search error: $e');
    }

    if (foundUnitLocation != null && foundUnitData != null) {
      _mapController.move(foundUnitLocation, 15.0);
      _showUnitMarkerDetails(foundUnitData);
      _showSnackBar('Menemukan unit: ${foundUnitData['nama']}', Colors.green);
      return;
    }

    setState(() => _isSearchingLocation = true);
    try {
      final client = HttpClient();
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=1');
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'siaga_tracker');
      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final List<dynamic> results = jsonDecode(responseBody);
        if (results.isNotEmpty) {
          final latStr = results[0]['lat'];
          final lngStr = results[0]['lon'];
          final displayName = results[0]['display_name'] ?? query;
          final double? lat = double.tryParse(latStr ?? '');
          final double? lng = double.tryParse(lngStr ?? '');

          if (lat != null && lng != null) {
            _mapController.move(LatLng(lat, lng), 14.0);
            _showSnackBar('Peta digeser ke: $displayName', Colors.blue);
          } else {
            _showSnackBar('Lokasi ditemukan tetapi koordinat tidak valid.', Colors.orange);
          }
        } else {
          _showSnackBar('Lokasi tidak ditemukan.', Colors.orange);
        }
      } else {
        _showSnackBar('Gagal menghubungi server geocoding.', Colors.orange);
      }
      client.close();
    } catch (e) {
      debugPrint('Geocoding error: $e');
      _showSnackBar('Pencarian error: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSearchingLocation = false);
      }
    }
  }

  Widget _buildMapStyleButton(IconData icon, String style, String label) {
    final String resolvedStyle = _mapStyle ?? 'standard';
    final isSelected = resolvedStyle == style;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mapStyle = style;
        });
      },
      child: Tooltip(
        message: label,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).primaryColor
                : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF18181B) : Colors.white),
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.white : Colors.grey,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildMapRefreshButton() {
    return GestureDetector(
      onTap: () async {
        _showSnackBar('Memperbarui data peta...', Colors.blue);
        setState(() {
          _mapRefreshKey++;
          _liveTrackingStream = widget.dbRef.child('live_tracking').onValue;
        });
        try {
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
          );
        } catch (_) {}
        _showSnackBar('Peta berhasil diperbarui!', Colors.green);
      },
      child: Tooltip(
        message: 'Perbarui Peta',
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF18181B) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: const Icon(
            Icons.refresh_rounded,
            color: Colors.blueAccent,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildRadarStatsCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  IconData _getVehicleIcon(String? vehicle) {
    if (vehicle == null) return Icons.local_police;
    final v = vehicle.toLowerCase().trim();
    if (v.contains('jalan kaki') || v.contains('jalan') || v.contains('kaki') || v.contains('pedestrian')) {
      return Icons.directions_walk;
    }
    if (v.contains('motor') || v.contains('trail') || v.contains('r2')) {
      return Icons.motorcycle;
    }
    if (v.contains('truk') || v.contains('truck') || v.contains('dalmas')) {
      return Icons.local_shipping;
    }
    if (v.contains('mobil') || v.contains('car') || v.contains('r4') || v.contains('sedan') || v.contains('patroli')) {
      return Icons.directions_car;
    }
    return Icons.shield_rounded; // Lainnya (Tameng Taktis)
  }

  void _showUnitMarkerDetails(Map<String, dynamic> u) {
    final updateTime = u['waktu'] != null 
        ? DateTime.tryParse(u['waktu'])?.toLocal() 
        : null;
    final timeStr = updateTime != null 
        ? '${updateTime.hour.toString().padLeft(2, '0')}:${updateTime.minute.toString().padLeft(2, '0')} WITA'
        : '-';
    final coord = Map<String, dynamic>.from(u['koordinat'] ?? {});
    final double accuracy = (coord['akurasi'] as num?)?.toDouble() ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        title: Row(
          children: [
            Icon(_getVehicleIcon(u['vehicle'] as String?), color: const Color(0xFF10B981)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                u['nama'] ?? 'Unit Detail',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NRP: ${u['nrp'] ?? "-"}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Text('Pangkat: ${u['pangkat'] ?? "-"}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Text('Satker: ${u['satker'] ?? "-"}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Divider(color: Theme.of(context).dividerColor),
              
              _buildDetailRow(context, 'Aktivitas:', u['jenis_giat'] ?? 'Pengamanan', isPrimary: true),
              _buildDetailRow(context, 'Kendaraan:', u['vehicle'] ?? '-'),
              _buildDetailRow(context, 'Komandan:', u['commander'] ?? 'Mandiri'),
              _buildDetailRow(context, 'Kekuatan:', '${u['jumlah_personel'] ?? 1} Anggota'),
              _buildDetailRow(context, 'Akurasi GPS:', accuracy > 0 ? '${accuracy.round()} meter' : '-'),
              _buildDetailRow(context, 'Deskripsi:', u['description'] ?? '-'),
              _buildDetailRow(context, 'Update:', timeStr, isSuccess: true),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3545)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, {bool isPrimary = false, bool isSuccess = false}) {
    Color valColor = Theme.of(context).colorScheme.onSurface;
    if (isPrimary) valColor = Colors.blueAccent;
    if (isSuccess) valColor = Colors.greenAccent;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valColor, fontSize: 12, fontWeight: (isPrimary || isSuccess) ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  void _showPoskoDetails(Map<String, dynamic> gf) {
    final name = gf['nama']?.toString() ?? 'Posko';
    final radius = gf['radius']?.toString() ?? '0';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        title: Row(
          children: [
            const Icon(Icons.flag_rounded, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Radius Geofence: $radius meter', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text('Lintang: ${gf['lat'] ?? "-"}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text('Bujur: ${gf['lng'] ?? "-"}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3545)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _showActiveUnitsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
      builder: (context) {
        return StreamBuilder<DatabaseEvent>(
          stream: widget.dbRef.child('live_tracking').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 40, color: Colors.orange[400]),
                      const SizedBox(height: 8),
                      Text('Gagal memuat daftar unit', style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(snapshot.error.toString(), style: TextStyle(color: Colors.grey[500], fontSize: 10), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            List<Map<String, dynamic>> activeList = [];
            if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
              final raw = snapshot.data!.snapshot.value;
              if (raw is Map) {
                raw.forEach((key, val) {
                  if (val is Map) {
                    try {
                      activeList.add(Map<String, dynamic>.from(val));
                    } catch (e) {
                      debugPrint('Error parsing active unit: $e');
                    }
                  }
                });
              } else if (raw is List) {
                for (var val in raw) {
                  if (val is Map) {
                    try {
                      activeList.add(Map<String, dynamic>.from(val));
                    } catch (e) {
                      debugPrint('Error parsing active unit: $e');
                    }
                  }
                }
              }
            }

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 15),
                  Text('Daftar Unit Aktif (Realtime)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  Expanded(
                    child: activeList.isEmpty
                        ? const Center(child: Text('Tidak ada unit aktif.', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: activeList.length,
                            itemBuilder: (context, index) {
                              final u = activeList[index];
                              final k = Map<String, dynamic>.from(u['koordinat'] ?? {});
                              final double lat = k['lat'] ?? 0.0;
                              final double lng = k['lng'] ?? 0.0;
                              
                              final updateTime = u['waktu'] != null 
                                  ? DateTime.tryParse(u['waktu'])?.toLocal() 
                                  : null;
                              final timeStr = updateTime != null 
                                  ? '${updateTime.hour.toString().padLeft(2, '0')}:${updateTime.minute.toString().padLeft(2, '0')}' 
                                  : '-';
                              
                              return Card(
                                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFF1F1F4),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    child: Icon(_getVehicleIcon(u['vehicle'] as String?), color: const Color(0xFF10B981)),
                                  ),
                                  title: Text('${u['pangkat'] ?? ''} ${u['nama'] ?? ''}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text('NRP: ${u['nrp'] ?? ''} | Satker: ${u['satker'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      Text('Giat: ${u['jenis_giat'] ?? ''}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
                                      Text('Kendaraan: ${u['vehicle'] ?? '-'} | Komandan: ${u['commander'] ?? 'Mandiri'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      Text('Kekuatan: ${u['jumlah_personel'] ?? 1} Pers | Update: $timeStr WITA', style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.navigation, color: Colors.blueAccent),
                                    onPressed: () {
                                      final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                                      ScaffoldMessenger.of(context).clearSnackBars();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Membuka rute ke Google Maps:\n$url'),
                                          duration: const Duration(milliseconds: 1000),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng centerPoint = widget.posisiSekarang != null
        ? LatLng(widget.posisiSekarang!.latitude, widget.posisiSekarang!.longitude)
        : const LatLng(-3.4402, 114.8306);

    return StreamBuilder<DatabaseEvent>(
      key: ValueKey('live_tracking_stream_$_mapRefreshKey'),
      stream: _liveTrackingStream,
      builder: (context, snapshot) {
        int activeCount = 0;
        List<Marker> mapMarkers = [];

        if (widget.posisiSekarang != null) {
          mapMarkers.add(
            Marker(
              width: 45.0,
              height: 45.0,
              point: LatLng(widget.posisiSekarang!.latitude, widget.posisiSekarang!.longitude),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6EFD).withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6EFD),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final raw = snapshot.data!.snapshot.value;
          if (raw is Map) {
            raw.forEach((key, val) {
              if (val is Map) {
                final u = Map<String, dynamic>.from(val);
                final k = Map<String, dynamic>.from(u['koordinat'] ?? {});
                final double? lat = k['lat'] as double?;
                final double? lng = k['lng'] as double?;

                if (lat != null && lng != null) {
                  activeCount++;
                  if (widget.nrp.isNotEmpty && u['nrp']?.toString().trim() == widget.nrp.trim()) return;

                  mapMarkers.add(
                    Marker(
                      width: 50.0,
                      height: 50.0,
                      point: LatLng(lat, lng),
                      child: GestureDetector(
                        onTap: () => _showUnitMarkerDetails(u),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                              ),
                              child: Icon(
                                _getVehicleIcon(u['vehicle'] as String?),
                                color: const Color(0xFF10B981),
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              }
            });
          }
        }

        for (final gf in widget.geofences) {
          final double? lat = gf['lat'] as double?;
          final double? lng = gf['lng'] as double?;
          if (lat != null && lng != null) {
            mapMarkers.add(
              Marker(
                width: 45.0,
                height: 45.0,
                point: LatLng(lat, lng),
                child: GestureDetector(
                  onTap: () => _showPoskoDetails(gf),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                        ),
                        child: const Icon(
                          Icons.flag_rounded,
                          color: Color(0xFFEF4444),
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }

        String mapUrl;
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final String resolvedStyle = _mapStyle ?? 'standard';

        switch (resolvedStyle) {
          case 'satellite':
            mapUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
            break;
          case 'osm':
            mapUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
            break;
          case 'standard':
          default:
            mapUrl = isDarkMode
                ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                : 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
            break;
        }

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: centerPoint,
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: mapUrl,
                  userAgentPackageName: 'siaga_tracker',
                ),
                CircleLayer(
                  circles: widget.geofences.map((gf) {
                    final double? lat = gf['lat'] as double?;
                    final double? lng = gf['lng'] as double?;
                    final double? radius = (gf['radius'] as num?)?.toDouble();
                    if (lat != null && lng != null && radius != null) {
                      return CircleMarker(
                        point: LatLng(lat, lng),
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderColor: Colors.amber,
                        borderStrokeWidth: 2,
                        useRadiusInMeter: true,
                        radius: radius,
                      );
                    }
                    return null;
                  }).whereType<CircleMarker>().toList(),
                ),
                MarkerLayer(markers: mapMarkers),
              ],
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).dividerColor),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                        onSubmitted: (value) => _searchLocation(value),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Cari Lokasi / Anggota Aktif...',
                          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                          icon: _isSearchingLocation
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.blueAccent)),
                                )
                              : const Icon(Icons.search, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    if (MediaQuery.of(context).viewInsets.bottom == 0) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).dividerColor),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'LEGENDA PETA',
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 6),
                            _buildLegendItem(const Color(0xFF10B981), 'Personel Aktif'),
                            const SizedBox(height: 4),
                            _buildLegendItem(const Color(0xFFEF4444), 'Posko'),
                            const SizedBox(height: 4),
                            _buildLegendItem(Colors.amber, 'Area Operasi'),
                            const SizedBox(height: 4),
                            _buildLegendItem(const Color(0xFF0D6EFD), 'Lokasi Saya'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),

                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildMapStyleButton(Icons.satellite_alt_rounded, 'satellite', 'Satelit'),
                              const SizedBox(height: 8),
                              _buildMapStyleButton(Icons.map_rounded, 'standard', 'Peta'),
                              const SizedBox(height: 8),
                              _buildMapStyleButton(Icons.explore_outlined, 'osm', 'OSM'),
                              const SizedBox(height: 8),
                              _buildMapRefreshButton(),
                            ],
                          ),
                        ),
                      ),
                    ],
                    
                    if (MediaQuery.of(context).viewInsets.bottom == 0) const Spacer(),

                    if (MediaQuery.of(context).viewInsets.bottom == 0) ...[
                      Row(
                        children: [
                          _buildRadarStatsCard('UNIT AKTIF', '$activeCount'),
                          const SizedBox(width: 10),
                          _buildRadarStatsCard('STATUS GPS', widget.gpsEnabled ? 'PRESISI TINGGI' : 'GPS MATI'),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).dividerColor),
                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3))],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.my_location_rounded, color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Menampilkan unit aktif Polda Kalsel di sekitar sektor Anda.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  _showActiveUnitsBottomSheet();
                                },
                                child: const Text('LIHAT DAFTAR', style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                              )
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// LIVE STREAMING SCREEN (Fase 2)
// ============================================================================
class LiveStreamingScreen extends StatefulWidget {
  final DatabaseReference dbRef;
  final String uid;
  final String nama;
  final String pangkat;
  final String nrp;
  final String satker;

  const LiveStreamingScreen({
    super.key,
    required this.dbRef,
    required this.uid,
    required this.nama,
    required this.pangkat,
    required this.nrp,
    required this.satker,
  });

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaRecorder? _mediaRecorder;
  String? _lastSavePath;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<StreamSubscription>> _viewerSubscriptions = {};
  StreamSubscription<DatabaseEvent>? _viewersAddedSubscription;
  StreamSubscription<DatabaseEvent>? _viewersChangedSubscription;
  StreamSubscription<DatabaseEvent>? _viewersRemovedSubscription;
  StreamSubscription<DatabaseEvent>? _activeStreamSubscription;
  bool _isVCActive = false;
  bool _isVCVideoActive = true;
  StreamSubscription<DatabaseEvent>? _vcActiveSubscription;
  StreamSubscription<DatabaseEvent>? _vcVideoActiveSubscription;
  
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = false;
  bool _isConnected = false;
  String _statusText = 'Menginisialisasi Kamera...';

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject'
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject'
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject'
      }
    ]
  };

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startStreaming();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<bool> _requestMediaPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();
    
    // Request storage access permissions
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    if (cameraStatus.isPermanentlyDenied || microphoneStatus.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _statusText = 'Izin kamera/mikrofon diblokir permanen. Aktifkan di Setelan.';
        });
      }
      return false;
    }

    if (!cameraStatus.isGranted || !microphoneStatus.isGranted) {
      if (mounted) {
        setState(() {
          _statusText = 'Izin kamera/mikrofon ditolak. Tidak dapat memulai siaran.';
        });
      }
      return false;
    }

    return true;
  }

  // Simpan timestamp viewer request terakhir yang diproses
  final Map<String, int> _processedViewerTimestamps = {};

  Future<void> _startStreaming() async {
    try {
      if (!await _requestMediaPermissions()) {
        return;
      }

      setState(() {
        _statusText = 'Membuka Kamera...';
      });

      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googEchoCancellation2': true,
          'googAutoGainControl': true,
          'googAutoGainControl2': true,
          'googNoiseSuppression': true,
          'googNoiseSuppression2': true,
          'googHighpassFilter': true,
          'googTypingNoiseDetection': true,
        },
        'video': {
          'mandatory': {},
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'optional': [
            {'minWidth': 640},
            {'minHeight': 360},
            {'minFrameRate': 30},
            {'width': 1280},
            {'height': 720},
          ],
        }
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      setState(() {
        _statusText = 'Mulai Menunggu Penonton...';
      });

      final streamRef = widget.dbRef.child('streams/${widget.uid}');
      
      // Bersihkan viewers lama
      await streamRef.child('viewers').remove();

      // Buat metadata info siaran
      await streamRef.child('info').set({
        'uid': widget.uid,
        'nrp': widget.nrp,
        'nama': widget.nama,
        'pangkat': widget.pangkat,
        'satker': widget.satker,
        'active': true,
        'startedAt': DateTime.now().toIso8601String(),
      });

      // Set untuk mencegah double-setup pada viewer yang sama
      final Set<String> _setupInProgress = {};

      Future<void> handleViewerRequest(String viewerId) async {
        if (_setupInProgress.contains(viewerId)) return; // sedang diproses, skip
        _setupInProgress.add(viewerId);
        try {
          if (_peerConnections.length >= 3 && !_peerConnections.containsKey(viewerId)) {
            debugPrint("[WebRTC] Penonton penuh, menolak: $viewerId");
            await streamRef.child('viewers/$viewerId/status').set('rejected_full');
            return;
          }
          // Bersihkan koneksi lama jika ada
          if (_peerConnections.containsKey(viewerId)) {
            debugPrint("[WebRTC] Viewer $viewerId re-init, teardown koneksi lama");
            _cleanupViewerConnection(viewerId);
          }
          debugPrint("[WebRTC] Setup koneksi untuk viewer: $viewerId");
          await _setupViewerConnection(viewerId);
        } finally {
          _setupInProgress.remove(viewerId);
        }
      }

      // onChildAdded: viewer BARU yang pertama kali masuk
      _viewersAddedSubscription = streamRef.child('viewers').onChildAdded.listen((event) async {
        final viewerId = event.snapshot.key;
        if (viewerId == null) return;
        final data = event.snapshot.value;
        if (data is Map) {
          final status = data['status']?.toString() ?? '';
          final timestamp = data['timestamp'] as int?;
          if (status == 'request') {
            if (timestamp != null) {
              if (_processedViewerTimestamps[viewerId] == timestamp) return;
              _processedViewerTimestamps[viewerId] = timestamp;
            }
            await handleViewerRequest(viewerId);
          }
        }
      });

      // onChildChanged: viewer LAMA yang menulis ulang status='request' (web reinisialisasi)
      _viewersChangedSubscription = streamRef.child('viewers').onChildChanged.listen((event) async {
        final viewerId = event.snapshot.key;
        if (viewerId == null) return;
        final data = event.snapshot.value;
        if (data is Map) {
          final status = data['status']?.toString() ?? '';
          final timestamp = data['timestamp'] as int?;
          if (status == 'request') {
            if (timestamp != null) {
              if (_processedViewerTimestamps[viewerId] == timestamp) return;
              _processedViewerTimestamps[viewerId] = timestamp;
            }
            await handleViewerRequest(viewerId);
          }
        }
      });

      // Dengarkan jika ada penonton yang keluar
      _viewersRemovedSubscription = streamRef.child('viewers').onChildRemoved.listen((event) {
        final viewerId = event.snapshot.key;
        if (viewerId != null) {
          debugPrint("[WebRTC] Penonton keluar: $viewerId");
          _cleanupViewerConnection(viewerId);
        }
      });

      // Dengarkan perintah stop dari Posko Admin
      _activeStreamSubscription = streamRef.child('info/active').onValue.listen((event) {
        if (!mounted) return;
        final val = event.snapshot.value;
        if (val == false) {
          debugPrint("[WebRTC] Dihentikan oleh Posko Admin");
          _stopStreaming();
          Navigator.of(context).pop();
        }
      });

      _vcActiveSubscription = streamRef.child('info/vcActive').onValue.listen((event) {
        if (!mounted) return;
        final val = event.snapshot.value;
        setState(() {
          _isVCActive = val == true;
        });
      });

      _vcVideoActiveSubscription = streamRef.child('info/vcVideoActive').onValue.listen((event) {
        if (!mounted) return;
        final val = event.snapshot.value;
        setState(() {
          _isVCVideoActive = val != false;
        });
      });

    } catch (e) {
      debugPrint('Error starting WebRTC stream: $e');
      setState(() {
        _statusText = 'Gagal Memulai Siaran: $e';
      });
    }
  }

  Future<void> _setupViewerConnection(String viewerId) async {
    try {
      final streamRef = widget.dbRef.child('streams/${widget.uid}');
      final viewerRef = streamRef.child('viewers/$viewerId');

      final pc = await createPeerConnection(_iceServers);
      _peerConnections[viewerId] = pc;
      _viewerSubscriptions[viewerId] = [];

      bool remoteDescriptionSet = false;
      final List<RTCIceCandidate> bufferedCandidates = [];

      pc.onTrack = (RTCTrackEvent event) async {
        debugPrint("Remote track received from $viewerId: ${event.track.kind}");
        MediaStream? stream;
        if (event.streams.isNotEmpty) {
          stream = event.streams[0];
        } else {
          _remoteStream ??= await createLocalMediaStream('remote_stream');
          _remoteStream!.addTrack(event.track);
          stream = _remoteStream;
        }
        setState(() {
          _remoteStream = stream;
          _remoteRenderer.srcObject = _remoteStream;
        });
        Helper.setSpeakerphoneOn(true);
      };

      pc.onAddStream = (MediaStream stream) {
        debugPrint("Remote stream added from $viewerId: ${stream.id}");
        setState(() {
          _remoteStream = stream;
          _remoteRenderer.srcObject = _remoteStream;
        });
        Helper.setSpeakerphoneOn(true);
      };

      pc.onRemoveStream = (MediaStream stream) {
        debugPrint("Remote stream removed from $viewerId: ${stream.id}");
        setState(() {
          if (_remoteStream?.id == stream.id) {
            _remoteStream = null;
            _remoteRenderer.srcObject = null;
          }
        });
      };

      for (var track in _localStream!.getTracks()) {
        try {
          final sender = await pc.addTrack(track, _localStream!);
          if (track.kind == 'video') {
            var parameters = sender.parameters;
            parameters.encodings?.forEach((encoding) {
              encoding.maxBitrate = 2500000; // 2.5 Mbps
              encoding.maxFramerate = 30;
            });
            await sender.setParameters(parameters);
            debugPrint("[WebRTC] Enforced 2.5 Mbps encoding bitrate for video sender");
          }
        } catch (e) {
          debugPrint("Error adding track ${track.kind}: $e");
        }
      }

      pc.onIceCandidate = (candidate) {
        viewerRef.child('candidates/streamer').push().set(candidate.toMap());
      };

      pc.onConnectionState = (state) {
        debugPrint("Connection state for $viewerId changed to: $state");
        if (mounted) {
          setState(() {
            _isConnected = _peerConnections.values.any((c) => c.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected);
            _statusText = _peerConnections.isNotEmpty
                ? 'PENONTON: ${_peerConnections.length} USER'
                : 'MENUNGGU KONEKSI WEB...';
          });
        }
      };

      // Dengarkan ICE Candidates dari viewer ini
      final receiverCandidatesSub = viewerRef.child('candidates/receiver').onChildAdded.listen((event) async {
        final data = event.snapshot.value;
        if (data != null) {
          final map = Map<String, dynamic>.from(data as Map);
          final candidate = RTCIceCandidate(
            map['candidate'] ?? '',
            map['sdpMid'] ?? '',
            map['sdpMLineIndex'] ?? 0,
          );
          if (remoteDescriptionSet) {
            await pc.addCandidate(candidate);
          } else {
            bufferedCandidates.add(candidate);
          }
        }
      });
      _viewerSubscriptions[viewerId]!.add(receiverCandidatesSub);

      // Dengarkan SDP Answer dari viewer ini
      final answerSub = viewerRef.child('sdp/answer').onValue.listen((event) async {
        final data = event.snapshot.value;
        if (data == null || remoteDescriptionSet) return;

        final map = Map<String, dynamic>.from(data as Map);
        final description = RTCSessionDescription(map['sdp'] ?? '', map['type']);
        await pc.setRemoteDescription(description);
        remoteDescriptionSet = true;
        for (var cand in bufferedCandidates) {
          await pc.addCandidate(cand);
        }
        bufferedCandidates.clear();
      });
      _viewerSubscriptions[viewerId]!.add(answerSub);

      // Buat SDP Offer khusus untuk viewer ini
      RTCSessionDescription offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });

      await pc.setLocalDescription(offer);

      await viewerRef.child('sdp/offer').set({
        'type': offer.type,
        'sdp': offer.sdp,
      });

      // Update status menjadi connected (approved)
      await viewerRef.child('status').set('connected');

      setState(() {
        _statusText = 'PENONTON: ${_peerConnections.length} USER';
      });

    } catch (e) {
      debugPrint('Error setting up connection for viewer $viewerId: $e');
    }
  }

  void _cleanupViewerConnection(String viewerId) {
    if (_viewerSubscriptions.containsKey(viewerId)) {
      for (var sub in _viewerSubscriptions[viewerId]!) {
        sub.cancel();
      }
      _viewerSubscriptions.remove(viewerId);
    }

    if (_peerConnections.containsKey(viewerId)) {
      final pc = _peerConnections[viewerId];
      pc?.close();
      pc?.dispose();
      _peerConnections.remove(viewerId);
    }

    if (mounted) {
      setState(() {
        _isConnected = _peerConnections.values.any((c) => c.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected);
        _statusText = _peerConnections.isNotEmpty
            ? 'PENONTON: ${_peerConnections.length} USER'
            : 'MENUNGGU KONEKSI WEB...';
      });
    }
  }

  Future<void> _toggleMute() async {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack != null) {
        _isMuted = !_isMuted;
        audioTrack.enabled = !_isMuted;
        setState(() {});
      }
    }
  }

  Future<void> _toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    if (_remoteStream != null) {
      _remoteStream!.getAudioTracks().forEach((track) {
        track.enabled = _isSpeakerOn;
      });
    }
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
        _isFrontCamera = !_isFrontCamera;
        setState(() {});
      }
    }
  }

  String _setMediaBitrates(String sdp, int bitrateKbps) {
    List<String> lines = sdp.split('\r\n');
    if (lines.length == 1) {
      lines = sdp.split('\n');
    }
    List<String> newLines = [];
    bool isVideoSection = false;

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      newLines.add(line);

      if (line.startsWith('m=video')) {
        isVideoSection = true;
      } else if (line.startsWith('m=')) {
        isVideoSection = false;
      }

      if (isVideoSection && (line.startsWith('m=video') || line.startsWith('c=IN'))) {
        String nextLine = (i + 1 < lines.length) ? lines[i + 1] : '';
        if (!nextLine.startsWith('b=AS:')) {
          newLines.add('b=AS:$bitrateKbps');
          newLines.add('b=TIAS:${bitrateKbps * 1000}');
        }
      }
    }
    return newLines.join('\r\n');
  }

  Future<void> _toggleLocalRecording() async {
    if (_mediaRecorder != null) {
      try {
        await _mediaRecorder!.stop();
        debugPrint("[MediaRecorder] Rekaman lokal dihentikan manual");
        
        bool success = false;
        if (_lastSavePath != null) {
          final internalFile = File(_lastSavePath!);
          if (await internalFile.exists() && await internalFile.length() > 0) {
            try {
              String folderPath = '/storage/emulated/0/Download/SIAGA';
              final siagaDir = Directory(folderPath);
              if (!await siagaDir.exists()) {
                await siagaDir.create(recursive: true);
              }
              final String fileName = _lastSavePath!.split('/').last;
              final publicPath = '$folderPath/$fileName';
              await internalFile.copy(publicPath);
              success = true;
              
              // Hapus file internal setelah berhasil dicopy
              await internalFile.delete();
            } catch (copyErr) {
              debugPrint("[MediaRecorder] Gagal copy ke public: $copyErr");
              // Biarkan success = false agar pesan internal muncul
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success 
                  ? 'Rekaman selesai! Disimpan di folder Download/SIAGA' 
                  : 'Rekaman selesai! Disimpan di memori internal aplikasi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (recErr) {
        debugPrint("[MediaRecorder] Gagal menghentikan rekaman: $recErr");
      }
      setState(() {
        _mediaRecorder = null;
      });
    } else {
      if (_localStream == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kamera belum aktif. Tidak dapat merekam.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      try {
        final dir = await getApplicationDocumentsDirectory();
        
        // Gunakan .mp4 karena Android mendukung penuh format ini (webm sering 0 byte)
        final String fileName = 'SIAGA_Live_${widget.nrp}_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final String savePath = '${dir.path}/$fileName';
        _lastSavePath = savePath;
        debugPrint("[MediaRecorder] Menyimpan rekaman lokal ke: $savePath");

        _mediaRecorder = MediaRecorder();
        await _mediaRecorder!.start(
          savePath,
          videoTrack: _localStream!.getVideoTracks().isNotEmpty
              ? _localStream!.getVideoTracks().first
              : null,
          audioChannel: RecorderAudioChannel.INPUT,
          rotationDegrees: 90, // Koreksi rotasi portrait agar rekaman tidak terbalik
        );
        debugPrint("[MediaRecorder] Rekaman lokal dimulai manual");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Merekam...'),
              backgroundColor: Colors.blueAccent,
            ),
          );
        }
        setState(() {});
      } catch (recErr) {
        debugPrint("[MediaRecorder] Gagal memulai rekaman manual: $recErr");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal memulai rekaman: $recErr'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _stopStreaming() async {
    try {
      await widget.dbRef.child('streams/${widget.uid}').remove();
    } catch (e) {
      debugPrint('Error removing stream reference: $e');
    }

    _activeStreamSubscription?.cancel();
    _viewersAddedSubscription?.cancel();
    _viewersChangedSubscription?.cancel();
    _viewersRemovedSubscription?.cancel();
    _vcActiveSubscription?.cancel();
    _vcVideoActiveSubscription?.cancel();

    // Hentikan semua koneksi viewer
    final viewerIds = List<String>.from(_peerConnections.keys);
    for (var vid in viewerIds) {
      _cleanupViewerConnection(vid);
    }

    // Hentikan rekaman lokal jika sedang berjalan
    if (_mediaRecorder != null) {
      try {
        await _mediaRecorder!.stop();
        debugPrint("[MediaRecorder] Rekaman lokal disimpan");
        if (mounted) {
          final isPublic = _lastSavePath?.contains('/Download/SIAGA') ?? false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isPublic 
                  ? 'Siaran selesai! Rekaman disimpan di folder Download/SIAGA' 
                  : 'Siaran selesai! Rekaman disimpan di memori internal aplikasi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (recErr) {
        debugPrint("[MediaRecorder] Gagal menghentikan rekaman lokal: $recErr");
      }
      _mediaRecorder = null;
    }

    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localStream?.dispose();

    _remoteStream?.getTracks().forEach((track) {
      track.stop();
    });
    _remoteStream?.dispose();

    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  @override
  void dispose() {
    _stopStreaming();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _localStream != null
                ? RTCVideoView(_localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Container(
                    color: Colors.black87,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
          ),

          // Video/Audio Dua Arah (Panggilan dari Komandan / Web)
          if (_isVCActive)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              right: 16,
              child: Container(
                width: 130,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey[950],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF10B981), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      if (_isVCVideoActive && _remoteStream != null)
                        RTCVideoView(
                          _remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      else if (_isVCVideoActive && _remoteStream == null)
                        const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF10B981),
                          ),
                        )
                      else
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.mic_none_rounded,
                                  color: Color(0xFF10B981),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'ADMIN/KOMANDAN\n(SUARA)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Positioned(
                        bottom: 6,
                        left: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                color: Color(0xFF10B981),
                                size: 10,
                              ),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'ADMIN/KOMANDAN',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
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
            ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isConnected ? Colors.red : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${widget.pangkat} ${widget.nama}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'NRP: ${widget.nrp} | ${widget.satker}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FloatingActionButton(
                      heroTag: 'mute_btn',
                      backgroundColor: _isMuted ? Colors.redAccent : Colors.grey[900],
                      foregroundColor: Colors.white,
                      onPressed: _toggleMute,
                      child: Icon(_isMuted ? Icons.mic_off_rounded : Icons.mic_rounded),
                    ),
                    const SizedBox(width: 14),
                    FloatingActionButton(
                      heroTag: 'speaker_btn',
                      backgroundColor: _isSpeakerOn ? Colors.grey[900] : Colors.redAccent,
                      foregroundColor: Colors.white,
                      onPressed: _toggleSpeaker,
                      child: Icon(_isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                    ),
                    const SizedBox(width: 14),
                    FloatingActionButton(
                      heroTag: 'switch_cam_btn',
                      backgroundColor: Colors.grey[900],
                      foregroundColor: Colors.white,
                      onPressed: _switchCamera,
                      child: const Icon(Icons.flip_camera_ios_rounded),
                    ),
                    const SizedBox(width: 14),
                    FloatingActionButton(
                      heroTag: 'record_btn',
                      backgroundColor: _mediaRecorder != null ? Colors.red : Colors.grey[900],
                      foregroundColor: Colors.white,
                      onPressed: _toggleLocalRecording,
                      child: Icon(
                        _mediaRecorder != null
                            ? Icons.radio_button_checked_rounded
                            : Icons.fiber_manual_record_outlined,
                        color: _mediaRecorder != null ? Colors.white : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                      elevation: 8,
                    ),
                    icon: const Icon(Icons.stop_circle_rounded),
                    label: const Text(
                      'HENTIKAN LIVE',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

