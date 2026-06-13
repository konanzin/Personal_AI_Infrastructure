import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('voiceConfirmBeforeSend', () {
    test('defaults to false to preserve voice auto-send', () async {
      final provider = SettingsProvider();

      await provider.loadVoiceSettings();

      expect(provider.voiceConfirmBeforeSend, isFalse);
    });

    test('persists opt-in confirmation setting', () async {
      final provider = SettingsProvider();

      await provider.setVoiceConfirmBeforeSend(true);

      final reloaded = SettingsProvider();
      await reloaded.loadVoiceSettings();
      expect(reloaded.voiceConfirmBeforeSend, isTrue);

      await reloaded.setVoiceConfirmBeforeSend(false);

      final disabled = SettingsProvider();
      await disabled.loadVoiceSettings();
      expect(disabled.voiceConfirmBeforeSend, isFalse);
    });
  });
}
