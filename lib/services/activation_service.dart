import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseStatus { locked, trial, full, trialAlreadyUsed }

class ActivationService {
  static const String _secretSaltPermanent = 'STUGRA_SCAN_SECRET_KEY_2026';
  static const String _secretSaltTrial = 'STUGRA_TRIAL_KEY_2026';
  static const String _trial2PublicKey = 'EtXGQQsylTZwTs1ZBsQxhPujIzjKDrDZQUpvNltTKlU';
  static const int trial2MaxDurationSeconds = 10 * 24 * 60 * 60;

  static const String _prefIsActivated = 'is_activated';
  static const String _prefIsTrial = 'is_trial';
  static const String _prefActivationCode = 'activation_code';
  static const String _prefTrialUsedBefore = 'trial_used_before';
  static const String _prefTrialStartTime = 'trial_start_time';
  static const String _prefTrialLastCheckTime = 'trial_last_check_time';
  static const String _prefTrialExamsCount = 'trial_exams_created_count';

  // مدة مفتاح TRIAL القديم فقط؛ لا تنطبق على TRIAL2.
  static const int trialDurationMilliseconds = 24 * 60 * 60 * 1000;

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

  static String generatePermanentCode(String deviceId) {
    final bytes = utf8.encode(deviceId + _secretSaltPermanent);
    final digest = sha256.convert(bytes).toString().toUpperCase();
    return 'STUG-' + digest.substring(0, 4) + '-' + digest.substring(4, 8);
  }

  static String generateTrialCode(String deviceId) {
    final bytes = utf8.encode(deviceId + _secretSaltTrial);
    final digest = sha256.convert(bytes).toString().toUpperCase();
    return 'TRIAL-' + digest.substring(0, 4) + '-' + digest.substring(4, 8);
  }

  static Future<Map<String, dynamic>?> _decodeAndVerifyTrial2(
    String token,
    String deviceId, {
    int? nowSeconds,
  }) async {
    try {
      final parts = token.trim().split('.');
      if (parts.length != 3 || parts[0] != 'TRIAL2') return null;

      final payloadBytes = _decodeBase64Url(parts[1]);
      final signatureBytes = _decodeBase64Url(parts[2]);
      if (signatureBytes.length != 64) return null;

      final publicKeyBytes = _decodeBase64Url(_trial2PublicKey);
      if (publicKeyBytes.length != 32) return null;

      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(signatureBytes, publicKey: publicKey);
      final isValidSignature = await algorithm.verify(
        payloadBytes,
        signature: signature,
      );
      if (!isValidSignature) return null;

      final decoded = jsonDecode(utf8.decode(payloadBytes));
      if (decoded is! Map<String, dynamic>) return null;

      final version = decoded['v'];
      final tokenDeviceId = decoded['d'];
      final issuedAt = decoded['iat'];
      final expiresAt = decoded['exp'];
      final nonce = decoded['n'];

      if (version != 1 ||
          tokenDeviceId is! String ||
          tokenDeviceId != deviceId ||
          issuedAt is! int ||
          expiresAt is! int ||
          nonce is! String ||
          nonce.isEmpty) {
        return null;
      }

      final duration = expiresAt - issuedAt;
      if (duration <= 0 || duration > trial2MaxDurationSeconds) return null;

      final now = nowSeconds ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if (issuedAt > now || expiresAt <= now) return null;

      return decoded;
    } catch (_) {
      return null;
    }
  }

  static List<int> _decodeBase64Url(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padding = (4 - normalized.length % 4) % 4;
    return base64.decode(normalized.padRight(normalized.length + padding, '='));
  }

  static Future<bool> verifyTrial2Token(
    String token,
    String deviceId, {
    int? nowSeconds,
  }) async {
    return await _decodeAndVerifyTrial2(
          token,
          deviceId,
          nowSeconds: nowSeconds,
        ) !=
        null;
  }

  static LicenseStatus verifyKey(String enteredKey, String deviceId) {
    final cleanCode = enteredKey.trim().toUpperCase();
    if (cleanCode == generatePermanentCode(deviceId)) return LicenseStatus.full;
    if (cleanCode == generateTrialCode(deviceId)) return LicenseStatus.trial;
    return LicenseStatus.locked;
  }

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

    if (savedCode != null && savedCode.startsWith('TRIAL2.')) {
      final payload = await _decodeAndVerifyTrial2(savedCode, deviceId);
      final lastCheckTime = prefs.getInt(_prefTrialLastCheckTime);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (payload == null || lastCheckTime == null || now < lastCheckTime) {
        await _expireTrial(prefs);
        return false;
      }
      await prefs.setInt(_prefTrialLastCheckTime, now);
      return true;
    }

    // الحفاظ على آلية التجربة القديمة كما كانت.
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

  static Future<LicenseStatus> getLicenseStatus() async {
    final active = await isActivated();
    if (!active) return LicenseStatus.locked;
    final prefs = await SharedPreferences.getInstance();
    final isTrial = prefs.getBool(_prefIsTrial) ?? false;
    return isTrial ? LicenseStatus.trial : LicenseStatus.full;
  }

  static Future<bool> isFullyActivated() async {
    return (await getLicenseStatus()) == LicenseStatus.full;
  }

  static Future<int> getRemainingTrialDays() async {
    final status = await getLicenseStatus();
    if (status == LicenseStatus.full) return 999;
    if (status != LicenseStatus.trial) return 0;

    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefActivationCode);
    if (savedCode != null && savedCode.startsWith('TRIAL2.')) {
      final payload = await _decodeAndVerifyTrial2(
        savedCode,
        await getDeviceId(),
      );
      if (payload == null) return 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remaining = (payload['exp'] as int) - now;
      if (remaining <= 0) return 0;
      return (remaining / (24 * 60 * 60)).ceil();
    }

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

  static Future<LicenseStatus> applyKey(String enteredKey) async {
    final originalInput = enteredKey.trim();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await getDeviceId();

    // حماية الترخيص الدائم من الاستبدال بمفتاح تجريبي.
    final alreadyActivated = prefs.getBool(_prefIsActivated) ?? false;
    final currentlyTrial = prefs.getBool(_prefIsTrial) ?? false;
    final currentlySavedCode = prefs.getString(_prefActivationCode);
    if (alreadyActivated &&
        !currentlyTrial &&
        currentlySavedCode == generatePermanentCode(deviceId)) {
      return LicenseStatus.full;
    }

    // Base64 حساس لحالة الأحرف؛ لا نحول TRIAL2 إلى أحرف كبيرة.
    if (originalInput.startsWith('TRIAL2.')) {
      final payload = await _decodeAndVerifyTrial2(originalInput, deviceId);
      if (payload == null) return LicenseStatus.locked;

      final trialUsedBefore = prefs.getBool(_prefTrialUsedBefore) ?? false;
      if (trialUsedBefore) return LicenseStatus.trialAlreadyUsed;

      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setBool(_prefIsActivated, true);
      await prefs.setBool(_prefIsTrial, true);
      await prefs.setBool(_prefTrialUsedBefore, true);
      await prefs.setString(_prefActivationCode, originalInput);
      await prefs.setInt(_prefTrialStartTime, now);
      await prefs.setInt(_prefTrialLastCheckTime, now);
      return LicenseStatus.trial;
    }

    final cleanCode = originalInput.toUpperCase();
    final status = verifyKey(cleanCode, deviceId);

    if (status == LicenseStatus.full) {
      await prefs.setBool(_prefIsActivated, true);
      await prefs.setBool(_prefIsTrial, false);
      await prefs.setString(_prefActivationCode, cleanCode);
      return LicenseStatus.full;
    }

    if (status == LicenseStatus.trial) {
      final trialUsedBefore = prefs.getBool(_prefTrialUsedBefore) ?? false;
      if (trialUsedBefore) return LicenseStatus.trialAlreadyUsed;

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
