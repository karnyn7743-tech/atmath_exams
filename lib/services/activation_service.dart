import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseStatus { locked, trial, full, trialAlreadyUsed }

class ActivationService {
  // يجب أن تبقى القيم والخوارزمية مطابقة لتطبيق المولّد.
  static const String _secretSaltPermanent = 'STUGRA_SCAN_SECRET_KEY_2026';
  static const String _secretSaltTrial = 'STUGRA_TRIAL_KEY_2026';

  // مفاتيح التخزين مطابقة لتطبيق إجزامس أوتوميشن.
  static const String _prefIsActivated = 'is_activated';
  static const String _prefIsTrial = 'is_trial';
  static const String _prefActivationCode = 'activation_code';
  static const String _prefTrialUsedBefore = 'trial_used_before';
  static const String _prefTrialStartTime = 'trial_start_time';
  static const String _prefTrialLastCheckTime = 'trial_last_check_time';
  static const String _prefTrialExamsCount = 'trial_exams_created_count';

  // المدة الحالية 24 ساعة كما في التطبيق الأصلي.
  // سنحدد المدة النهائية لاحقاً بصورة مستقلة.
  static const int trialDurationMilliseconds = 24 * 60 * 60 * 1000;

  /// استخراج معرّف الجهاز بالطريقة نفسها المستخدمة في تطبيق المولّد.
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'UNKNOWN_DEVICE';
    }

    return 'UNKNOWN_DEVICE';
  }

  /// توليد مفتاح الترخيص الدائم بنفس خوارزمية المولّد.
  static String generatePermanentCode(String deviceId) {
    final bytes = utf8.encode(deviceId + _secretSaltPermanent);
    final digest = sha256.convert(bytes).toString().toUpperCase();
    final part1 = digest.substring(0, 4);
    final part2 = digest.substring(4, 8);
    return 'STUG-$part1-$part2';
  }

  /// توليد مفتاح التجربة بنفس خوارزمية المولّد.
  static String generateTrialCode(String deviceId) {
    final bytes = utf8.encode(deviceId + _secretSaltTrial);
    final digest = sha256.convert(bytes).toString().toUpperCase();
    final part1 = digest.substring(0, 4);
    final part2 = digest.substring(4, 8);
    return 'TRIAL-$part1-$part2';
  }

  /// تحديد نوع المفتاح المدخل للجهاز الحالي.
  static LicenseStatus verifyKey(String enteredKey, String deviceId) {
    final cleanCode = enteredKey.trim().toUpperCase();

    if (cleanCode == generatePermanentCode(deviceId)) {
      return LicenseStatus.full;
    }

    if (cleanCode == generateTrialCode(deviceId)) {
      return LicenseStatus.trial;
    }

    return LicenseStatus.locked;
  }

  /// فحص صلاحية التشغيل الحالية، مع حماية ساعة الهاتف كما في الأصل.
  static Future<bool> isActivated() async {
    final prefs = await SharedPreferences.getInstance();
    final activated = prefs.getBool(_prefIsActivated) ?? false;
    if (!activated) return false;

    final isTrial = prefs.getBool(_prefIsTrial) ?? false;
    final savedCode = prefs.getString(_prefActivationCode);
    final deviceId = await getDeviceId();

    if (!isTrial) {
      return savedCode == generatePermanentCode(deviceId);
    }

    final expectedTrial = generateTrialCode(deviceId);
    if (savedCode != expectedTrial) {
      await _expireTrial(prefs);
      return false;
    }

    final startTime = prefs.getInt(_prefTrialStartTime);
    final lastCheckTime = prefs.getInt(_prefTrialLastCheckTime);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (startTime == null || lastCheckTime == null || now < lastCheckTime) {
      await _expireTrial(prefs);
      return false;
    }

    if (now - startTime > trialDurationMilliseconds) {
      await _expireTrial(prefs);
      return false;
    }

    await prefs.setInt(_prefTrialLastCheckTime, now);
    return true;
  }

  /// حالة الترخيص التي تستخدمها نقطة تشغيل التطبيق.
  static Future<LicenseStatus> getLicenseStatus() async {
    final active = await isActivated();
    if (!active) return LicenseStatus.locked;

    final prefs = await SharedPreferences.getInstance();
    final isTrial = prefs.getBool(_prefIsTrial) ?? false;
    return isTrial ? LicenseStatus.trial : LicenseStatus.full;
  }

  /// فحص هل التطبيق مفعل تفعيلاً كاملاً.
  static Future<bool> isFullyActivated() async {
    return (await getLicenseStatus()) == LicenseStatus.full;
  }

  /// الإبقاء على الواجهة الحالية التي تعرض الأيام المتبقية.
  /// مدة الـ24 ساعة تظهر يوماً واحداً ما دامت التجربة سارية.
  static Future<int> getRemainingTrialDays() async {
    final status = await getLicenseStatus();
    if (status == LicenseStatus.full) return 999;
    if (status != LicenseStatus.trial) return 0;

    final prefs = await SharedPreferences.getInstance();
    final startTime = prefs.getInt(_prefTrialStartTime);
    if (startTime == null) return 1;

    final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
    return elapsed < trialDurationMilliseconds ? 1 : 0;
  }

  static Future<int> getTrialCreatedCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefTrialExamsCount) ?? 0;
  }

  static Future<void> incrementTrialCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefTrialExamsCount) ?? 0;
    await prefs.setInt(_prefTrialExamsCount, current + 1);
  }

  /// حفظ المفتاح والتحقق منه، مع منع إعادة استخدام التجربة على الجهاز
  /// ما دامت بيانات التطبيق المحلية باقية، وفق آلية التطبيق الأصلي.
  static Future<LicenseStatus> applyKey(String enteredKey) async {
    final cleanCode = enteredKey.trim().toUpperCase();
    final deviceId = await getDeviceId();
    final status = verifyKey(cleanCode, deviceId);
    final prefs = await SharedPreferences.getInstance();

    if (status == LicenseStatus.full) {
      await prefs.setBool(_prefIsActivated, true);
      await prefs.setBool(_prefIsTrial, false);
      await prefs.setString(_prefActivationCode, cleanCode);
      return LicenseStatus.full;
    }

    if (status == LicenseStatus.trial) {
      final trialUsedBefore =
          prefs.getBool(_prefTrialUsedBefore) ?? false;
      if (trialUsedBefore) {
        return LicenseStatus.trialAlreadyUsed;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setBool(_prefIsActivated, true);
      await prefs.setBool(_prefIsTrial, true);
      await prefs.setBool(_prefTrialUsedBefore, true);
      await prefs.setString(_prefActivationCode, cleanCode);
      await prefs.setInt(_prefTrialStartTime, now);
      await prefs.setInt(_prefTrialLastCheckTime, now);
      return LicenseStatus.trial;
    }

    return LicenseStatus.locked;
  }

  static Future<void> _expireTrial(SharedPreferences prefs) async {
    await prefs.setBool(_prefIsActivated, false);
    await prefs.remove(_prefActivationCode);
  }
}
