import 'package:http/http.dart' as http;

import 'anthropic.dart';
import 'deepseek.dart';
import 'gemini.dart';
import 'openai.dart';
import 'yz.dart';

/// Ayarlarda seçilebilen sağlayıcılar.
const desteklenenSaglayicilar = Saglayici.values;

/// Seçili sağlayıcının istemcisini oluşturur.
YzIstemcisi istemciOlustur({
  required YzModeli model,
  required String apiAnahtari,
  http.Client? httpIstemcisi,
  Duration? tekrarBeklemesi,
}) => switch (model.saglayici) {
  Saglayici.anthropic => AnthropicIstemcisi(
    apiAnahtari: apiAnahtari,
    model: model,
    httpIstemcisi: httpIstemcisi,
    tekrarBeklemesi: tekrarBeklemesi,
  ),
  Saglayici.openai => OpenAiIstemcisi(
    apiAnahtari: apiAnahtari,
    model: model,
    httpIstemcisi: httpIstemcisi,
    tekrarBeklemesi: tekrarBeklemesi,
  ),
  Saglayici.gemini => GeminiIstemcisi(
    apiAnahtari: apiAnahtari,
    model: model,
    httpIstemcisi: httpIstemcisi,
    tekrarBeklemesi: tekrarBeklemesi,
  ),
  Saglayici.deepseek => DeepSeekIstemcisi(
    apiAnahtari: apiAnahtari,
    model: model,
    httpIstemcisi: httpIstemcisi,
    tekrarBeklemesi: tekrarBeklemesi,
  ),
};
