import 'package:flutter_test/flutter_test.dart';
import 'package:atmath_exams/services/activation_service.dart';

void main() {
  const validToken = 'TRIAL2.eyJ2IjoxLCJkIjoiVEVTVC1ERVZJQ0UtVkVSSUZZLTAwMyIsImlhdCI6MTc5NTI4ODg0NywiZXhwIjoxNzk2MTUyODQ3LCJuIjoiWHpIc0Q5NGhSRWdiZE1ITnlFR2MzQSJ9.uQMZO9htnmE4n4H2UyU6wiOm2zPHKvLwfNHr6Seap_mlvYh7VJjyyDMShCT4AjLUhjpAvyiUwVekG-BeFmMqBg';
  const deviceId = 'TEST-DEVICE-VERIFY-003';
  const issuedAt = 1795288847;

  test('accepts a valid signed TRIAL2 token for its device', () async {
    expect(
      await ActivationService.verifyTrial2Token(
        validToken,
        deviceId,
        nowSeconds: issuedAt + 30,
      ),
      isTrue,
    );
  });

  test('rejects a token with a modified payload', () async {
    final altered = validToken.replaceFirst('VEVSSUZZ', 'VEVSSUZY');
    expect(
      await ActivationService.verifyTrial2Token(
        altered,
        deviceId,
        nowSeconds: issuedAt + 30,
      ),
      isFalse,
    );
  });

  test('rejects a token for another device', () async {
    expect(
      await ActivationService.verifyTrial2Token(
        validToken,
        'ANOTHER-DEVICE',
        nowSeconds: issuedAt + 30,
      ),
      isFalse,
    );
  });

  test('rejects an expired token', () async {
    expect(
      await ActivationService.verifyTrial2Token(
        validToken,
        deviceId,
        nowSeconds: 1796152847,
      ),
      isFalse,
    );
  });

  test('rejects a token before its issue time', () async {
    expect(
      await ActivationService.verifyTrial2Token(
        validToken,
        deviceId,
        nowSeconds: issuedAt - 1,
      ),
      isFalse,
    );
  });
}
