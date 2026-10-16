import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  // Prevent platform messages on early channels (e.g. flutter/lifecycle) from overflowing buffer before listener registers
  channelBuffers.resize('flutter/lifecycle', 100);

  WidgetsFlutterBinding.ensureInitialized();

  // In release mode, silence debug prints to protect diagnostics and console cleanliness
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Forward Flutter errors, suppressing transient Web ViewInsets & DOMException assertion race conditions
  FlutterError.onError = (FlutterErrorDetails details) {
    final errStr = details.exceptionAsString();
    if (errStr.contains('ViewInsets cannot be negative') ||
        errStr.contains('_viewInsets.isNonNegative') ||
        (kIsWeb && errStr.contains('DOMException'))) {
      return;
    }
    if (!kReleaseMode) {
      FlutterError.dumpErrorToConsole(details);
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final errStr = error.toString();
    if (errStr.contains('ViewInsets cannot be negative') ||
        errStr.contains('_viewInsets.isNonNegative') ||
        (kIsWeb && errStr.contains('DOMException'))) {
      return true; // Mark as handled to avoid crashing the engine zone
    }
    if (!kReleaseMode) {
      debugPrint('[PlatformDispatcher ERROR] $error\n$stack');
    }
    return false;
  };

  // Prevent silent blank screens on widget build crashes, suppressing transient DOM exceptions on web
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final errStr = details.exceptionAsString();
    if (kIsWeb &&
        (errStr.contains('DOMException') ||
            errStr.contains('ViewInsets cannot be negative') ||
            errStr.contains('_viewInsets.isNonNegative'))) {
      return const SizedBox.shrink();
    }
    if (!kReleaseMode) {
      FlutterError.dumpErrorToConsole(details);
    }
    return Material(
      color: const Color(0xFFF7F1EC),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFD86A62), size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Rendering Error',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2C2523)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kReleaseMode ? 'A temporary display issue occurred.' : details.exceptionAsString(),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6E625D)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  // Set system UI overlay style matching warm light palette
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const ProviderScope(
      child: AttendHubApp(),
    ),
  );
}
