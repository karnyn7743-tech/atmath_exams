/// أدوات التحقق من قيمة رمز QR واستخراج الرقم السري منه.
class QRScannerService {
  static bool isValidQRCode(String qrCode) {
    return qrCode.trim().length >= 4;
  }

  /// يدعم الرقم السري المباشر أو الصيغة الاختيارية STUDENT:12345.
  static String extractSecretCode(String qrCode) {
    final value = qrCode.trim();
    final prefixed = RegExp(r'^STUDENT\s*:\s*(.+)$', caseSensitive: false)
        .firstMatch(value);
    return (prefixed?.group(1) ?? value).trim();
  }
}
