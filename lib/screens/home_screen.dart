import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/activation_service.dart';
import 'activation_screen.dart';
import 'document_hub_screen.dart';
import 'fetch_grades_screen.dart';
import 'fetch_grade_screen.dart';
import 'grade_screen.dart';
import 'scan_qr_screen.dart';
import 'grade_scanner_screen.dart';
import 'manual_grade_entry_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isActivated = false;
  int _remainingDays = 0;
  bool _isOfficialMode = false;

  @override
  void initState() {
    super.initState();
    _checkActivationStatus();
  }

  Future<void> _checkActivationStatus() async {
    try {
      final status = await ActivationService.getLicenseStatus();
      final remaining = await ActivationService.getRemainingTrialDays();

      if (!mounted) return;
      setState(() {
        _isActivated = status == LicenseStatus.full;
        _remainingDays = remaining;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر التحقق من حالة التفعيل: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _openActivationScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActivationScreen()),
    );
    if (mounted) await _checkActivationStatus();
  }

  Future<void> _openDocumentHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DocumentHubScreen(isOfficial: _isOfficialMode)),
    );
    if (mounted) await _checkActivationStatus();
  }

  void _openGradeScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isOfficialMode
            ? const GradeEntryScreen()
            : const GradeScannerScreen(),
      ),
    );
  }

  void _openOfficialQrScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanQRScreen()),
    );
  }

  void _openManualGradeEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManualGradeEntryScreen()),
    );
  }

  void _openFetchGradesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isOfficialMode
            ? const FetchMahsalaScreen()
            : const FetchGradesScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F0E7),
      appBar: AppBar(
        title: const Text(
          'أتمتة الاختبارات الشهرية والنهائية',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF52796F),
        elevation: 2,
        actions: [
          if (!_isActivated)
            IconButton(
              icon: const Icon(Icons.key, color: Colors.amberAccent),
              tooltip: 'تنشيط النسخة الكاملة',
              onPressed: _openActivationScreen,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isActivated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.brown, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _remainingDays > 0
                          ? 'الفترة التجريبية: متبقي لديك $_remainingDays يوماً.'
                          : 'انتهت الفترة التجريبية للاختبار المجاني.',
                      style: const TextStyle(
                        color: Colors.brown,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openActivationScreen,
                    child: const Text(
                      'تنشيط الآن',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          textStyle: WidgetStateProperty.all(
                            const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.white
                                : const Color(0xFF172554),
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? const Color(0xFF123B67)
                                : const Color(0xFFE2E8F0),
                          ),
                          side: WidgetStateProperty.all(
                            const BorderSide(color: Color(0xFF334155), width: 1.5),
                          ),
                        ),
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('ملف أعمال السنة'),
                            icon: Icon(Icons.menu_book),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('الكشوفات الرسمية'),
                            icon: Icon(Icons.assignment),
                          ),
                        ],
                        selected: {_isOfficialMode},
                        onSelectionChanged: (value) {
                          setState(() => _isOfficialMode = value.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildMainActionButton(
                      title: 'فتح وتحرير ملفات Word وPDF',
                      icon: Icons.article_outlined,
                      onTap: _openDocumentHub,
                      backgroundColor: const Color(0xFF334155),
                    ),
                    const SizedBox(height: 15),
                    _buildMainActionButton(
                      title: 'إدخال الدرجات من أوراق الاختبارات',
                      icon: Icons.qr_code_scanner,
                      onTap: _openGradeScanner,
                      backgroundColor: const Color(0xFF075985),
                    ),
                    if (_isOfficialMode) ...[
                      const SizedBox(height: 15),
                      _buildMainActionButton(
                        title: 'التعرف على الطالب بمسح رمز QR',
                        icon: Icons.qr_code_2,
                        onTap: _openOfficialQrScanner,
                        backgroundColor: const Color(0xFF5B21B6),
                      ),
                    ],
                    if (!_isOfficialMode) ...[
                      const SizedBox(height: 15),
                      _buildMainActionButton(
                        title: 'إدخال بقية درجات أعمال السنة',
                        icon: Icons.playlist_add_check,
                        onTap: _openManualGradeEntry,
                        backgroundColor: const Color(0xFF166534),
                      ),
                    ],
                    const SizedBox(height: 15),
                    _buildMainActionButton(
                      title: _isOfficialMode
                          ? 'جلب المحصلات م١ وم٢ إلى الكشوفات الرسمية'
                          : 'جلب درجات أعمال السنة إلى الكشوفات الرسمية',
                      icon: Icons.sync_alt,
                      onTap: _openFetchGradesScreen,
                      backgroundColor: const Color(0xFF9A3412),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEBE8DD),
              border: Border(
                top: BorderSide(color: Colors.green.shade200, width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إعداد وتطوير: أ. فواز سنان البعيثي',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          const ClipboardData(text: '00967778064679'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ رقم الواتساب: 00967778064679'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_android, size: 14, color: Color(0xFF1B5E20)),
                          SizedBox(width: 4),
                          Text(
                            'واتساب: 778064679',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          const ClipboardData(text: 'https://t.me/fawaz132'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ رابط قناة التليجرام'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send_rounded, size: 14, color: Color(0xFF0284C7)),
                          SizedBox(width: 4),
                          Text(
                            'تليجرام: @fawaz132',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
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
        ],
      ),
    );
  }

  Widget _buildMainActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color backgroundColor = const Color(0xFF718B79),
  }) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            backgroundColor,
            backgroundColor,
          ],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFF0F172A), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 19),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFFECE9DF),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
