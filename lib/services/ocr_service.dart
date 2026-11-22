import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// خدمة OCR مستقلة. يتولى GradeEntryScreen حالياً قص مناطق الدرجة والتعرف عليها.
class OCRService {
  late final TextRecognizer _textRecognizer;
  bool _isClosed = false;

  OCRService() {
    _textRecognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );
  }

  Future<String?> recognizeTextFromFile(String filePath) async {
    if (_isClosed) throw StateError('تم إغلاق خدمة التعرف الضوئي.');
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text.trim();
    } catch (e) {
      return null;
    }
  }

  Future<String?> recognizeTextFromBytes(Uint8List imageBytes) async {
    if (_isClosed) throw StateError('تم إغلاق خدمة التعرف الضوئي.');
    String? tempPath;
    try {
      final tempDir = await getTemporaryDirectory();
      tempPath = '${tempDir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.png';
      await File(tempPath).writeAsBytes(imageBytes, flush: true);
      return await recognizeTextFromFile(tempPath);
    } catch (e) {
      return null;
    } finally {
      if (tempPath != null) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      }
    }
  }

  Future<String?> recognizeTextFromImage(img.Image image) {
    return recognizeTextFromBytes(Uint8List.fromList(img.encodePng(image)));
  }

  Future<String?> recognizeGradeFromImage(img.Image image) async {
    final text = await recognizeTextFromImage(image);
    if (text == null) return null;
    final match = RegExp(r'[0-9٠-٩۰-۹]+(?:[.,][0-9٠-٩۰-۹]+)?').firstMatch(text);
    if (match == null) return null;
    return _convertArabicNumbers(match.group(0)!).replaceAll(',', '.');
  }

  Future<String?> recognizeSubjectIdFromImage(img.Image image) async {
    final text = await recognizeTextFromImage(image);
    if (text == null) return null;
    final match = RegExp(r'[0-9٠-٩۰-۹]+').firstMatch(text);
    return match == null ? null : _convertArabicNumbers(match.group(0)!);
  }

  String _convertArabicNumbers(String input) {
    const digits = {
      '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
      '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
      '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
      '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    };
    var result = input;
    digits.forEach((key, value) => result = result.replaceAll(key, value));
    return result;
  }

  void dispose() {
    if (_isClosed) return;
    _isClosed = true;
    _textRecognizer.close();
  }
}
