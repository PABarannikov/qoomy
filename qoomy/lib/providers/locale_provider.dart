import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('ru')); // Russian by default

  void setLocale(Locale locale) {
    if (locale.languageCode == 'en' || locale.languageCode == 'ru') {
      state = locale;
    }
  }

  void toggleLocale() {
    state = state.languageCode == 'ru'
        ? const Locale('en')
        : const Locale('ru');
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});
