package com.enesilhan.takvim_takip

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * Takvim Takip ana ekran widget'larının ortak kısmı.
 *
 * Verinin tamamını Dart tarafı hesaplar (lib/logic/widget_verisi.dart) ve
 * "widget_verisi" anahtarıyla JSON olarak yazar; burada yalnızca gösterilir.
 */
abstract class TakvimWidget : HomeWidgetProvider() {

    /** "gun", "hafta" ya da "ay": JSON'daki bölüm ve dokununca açılacak görünüm. */
    abstract val tur: String

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id -> ciz(context, appWidgetManager, id, widgetData) }
    }

    /** Widget büyütülüp küçültülünce yeniden çiz (sonraki planlar listesi). */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        ciz(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun ciz(
        context: Context,
        yonetici: AppWidgetManager,
        id: Int,
        veri: SharedPreferences,
    ) {
        val v = RemoteViews(context.packageName, R.layout.widget_takvim)
        val json = veri.getString("widget_verisi", null)?.let {
            try { JSONObject(it) } catch (e: Exception) { null }
        }

        // Widget'a dokununca uygulama ilgili görünümde açılır.
        v.setOnClickPendingIntent(
            R.id.widget_kok,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("takvimtakip://$tur"),
            ),
        )

        if (json == null) {
            v.setTextViewText(R.id.baslik, "Takvim Takip")
            v.setTextViewText(R.id.odak_baslik, "Uygulamayı bir kez aç")
            yonetici.updateAppWidget(id, v)
            return
        }

        val sayac = json.getJSONObject(tur)
        val yapilan = sayac.getInt("yapilan")
        val toplam = sayac.getInt("toplam")
        v.setTextViewText(R.id.baslik, sayac.getString("baslik"))
        v.setTextViewText(R.id.sayi, if (toplam == 0) "—" else "$yapilan/$toplam")

        if (tur == "hafta") {
            v.setViewVisibility(R.id.ilerleme, View.GONE)
            v.setViewVisibility(R.id.grafik, View.VISIBLE)
            v.setImageViewBitmap(R.id.grafik, haftaGrafigi(context, json))
        } else {
            v.setViewVisibility(R.id.grafik, View.GONE)
            v.setViewVisibility(R.id.ilerleme, View.VISIBLE)
            v.setProgressBar(
                R.id.ilerleme, 100, if (toplam == 0) 0 else yapilan * 100 / toplam, false,
            )
        }

        val secenekler = yonetici.getAppWidgetOptions(id)
        val yukseklik = secenekler.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        val buyuk = yukseklik >= 190
        val kucuk = yukseklik in 1..129

        val odak = json.optJSONObject("odak")
        if (odak == null) {
            v.setTextViewText(R.id.odak_ust, "")
            v.setTextViewText(R.id.odak_baslik, "Yaklaşan plan yok")
            v.setViewVisibility(R.id.odak_not, View.GONE)
            v.setViewVisibility(R.id.yapildi_butonu, View.GONE)
        } else {
            val ust = listOf(
                odak.getString("etiket"), odak.getString("saat"), odak.getString("ne_zaman"),
            ).filter { it.isNotEmpty() }.joinToString(" · ")
            v.setTextViewText(R.id.odak_ust, ust)
            val sabit = if (odak.getBoolean("sabit")) "📌 " else ""
            v.setTextViewText(R.id.odak_baslik, sabit + odak.getString("baslik"))

            val not = odak.getString("not")
            v.setTextViewText(R.id.odak_not, not)
            v.setViewVisibility(
                R.id.odak_not, if (not.isEmpty() || kucuk) View.GONE else View.VISIBLE,
            )

            if (odak.getBoolean("isaretlenebilir")) {
                v.setViewVisibility(R.id.yapildi_butonu, View.VISIBLE)
                v.setOnClickPendingIntent(
                    R.id.yapildi_butonu,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context, Uri.parse("takvimtakip://yapildi?id=${odak.getInt("plan_id")}"),
                    ),
                )
            } else {
                v.setViewVisibility(R.id.yapildi_butonu, View.GONE)
            }
        }

        val sonrakiler = json.optJSONArray("sonrakiler")
        val satirlar = intArrayOf(R.id.sonraki_1, R.id.sonraki_2, R.id.sonraki_3)
        val adet = sonrakiler?.length() ?: 0
        v.setViewVisibility(R.id.sonrakiler, if (buyuk && adet > 0) View.VISIBLE else View.GONE)
        satirlar.forEachIndexed { i, satir ->
            if (i < adet) {
                val s = sonrakiler!!.getJSONObject(i)
                v.setTextViewText(satir, "${s.getString("zaman")}  ${s.getString("baslik")}")
                v.setViewVisibility(satir, View.VISIBLE)
            } else {
                v.setViewVisibility(satir, View.GONE)
            }
        }

        yonetici.updateAppWidget(id, v)
    }

    /** Haftanın 7 günü için tamamlanma çubukları (Pzt–Paz). */
    private fun haftaGrafigi(context: Context, json: JSONObject): Bitmap {
        val gunler = json.getJSONArray("hafta_gunleri")
        val yogunluk = context.resources.displayMetrics.density
        val g = (300 * yogunluk).toInt()
        val y = (46 * yogunluk).toInt()
        val bmp = Bitmap.createBitmap(g, y, Bitmap.Config.ARGB_8888)
        val tuval = Canvas(bmp)

        fun renk(id: Int) = context.getColor(id)
        val iz = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = renk(R.color.widget_iz) }
        val dolu = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = renk(R.color.widget_tamam) }
        val yazi = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = renk(R.color.widget_ikincil)
            textSize = 10 * yogunluk
            textAlign = Paint.Align.CENTER
        }
        val bugunYazi = Paint(yazi).apply {
            color = renk(R.color.widget_vurgu)
            typeface = Typeface.DEFAULT_BOLD
        }

        val sutun = g / 7f
        val cubukGenislik = sutun * 0.42f
        val yaziAlani = 14 * yogunluk
        val cubukYukseklik = y - yaziAlani - 2 * yogunluk
        val yaricap = 3 * yogunluk

        for (i in 0 until gunler.length()) {
            val gun = gunler.getJSONObject(i)
            val orta = sutun * i + sutun / 2
            val sol = orta - cubukGenislik / 2
            tuval.drawRoundRect(
                RectF(sol, 0f, sol + cubukGenislik, cubukYukseklik), yaricap, yaricap, iz,
            )
            if (!gun.isNull("oran")) {
                val oran = gun.getDouble("oran").toFloat().coerceIn(0f, 1f)
                if (oran > 0f) {
                    val ust = cubukYukseklik * (1 - oran)
                    tuval.drawRoundRect(
                        RectF(sol, ust, sol + cubukGenislik, cubukYukseklik), yaricap, yaricap, dolu,
                    )
                }
            }
            tuval.drawText(
                gun.getString("ad"), orta, y - 2 * yogunluk,
                if (gun.getBoolean("bugun")) bugunYazi else yazi,
            )
        }
        return bmp
    }
}

class GunlukWidget : TakvimWidget() {
    override val tur = "gun"
}

class HaftalikWidget : TakvimWidget() {
    override val tur = "hafta"
}

class AylikWidget : TakvimWidget() {
    override val tur = "ay"
}
