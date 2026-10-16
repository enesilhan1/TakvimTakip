import 'package:flutter/material.dart';

void main() {
  runApp(const TakvimTakipApp());
}

class TakvimTakipApp extends StatelessWidget {
  const TakvimTakipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Takvim Takip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const _BaslangicEkrani(),
    );
  }
}

/// Geçici ekran. Aşama 3'te gün görünümü ile değiştirilecek.
class _BaslangicEkrani extends StatelessWidget {
  const _BaslangicEkrani();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Takvim Takip')),
      body: const Center(child: Text('Yakında burada planların olacak.')),
    );
  }
}
