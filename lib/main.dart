import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/focus_timer_provider.dart';
import 'pages/main_shell_page.dart';

void main() {
  runApp(const FocusTimerApp());
}

class FocusTimerApp extends StatelessWidget {
  const FocusTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FocusTimerProvider(),
      child: MaterialApp(
        title: '专注时钟',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
          useMaterial3: true,
        ),
        home: const MainShellPage(),
      ),
    );
  }
}
