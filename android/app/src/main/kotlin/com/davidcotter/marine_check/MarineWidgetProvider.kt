package com.davidcotter.marine_check

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.graphics.Color
import android.view.View
import es.antonborri.home_widget.HomeWidgetPlugin
import android.app.PendingIntent
import android.content.Intent
import android.graphics.BitmapFactory
import java.io.File

import android.util.Log

class MarineWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        // Iterate over all widgets of this class
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            WidgetConfigurationActivity.deleteLocationId(context, appWidgetId)
        }
    }
}

internal fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
    // Get data from SharedPreferences (via HomeWidgetPlugin)
    val widgetData = HomeWidgetPlugin.getData(context)
    
    // Check if we have a specific location for this widget
    val savedLocationId = WidgetConfigurationActivity.loadLocationId(context, appWidgetId)
    val suffix = if (savedLocationId != null && savedLocationId != "follow_app") "_$savedLocationId" else ""

    val location = widgetData.getString("location_name$suffix", widgetData.getString("location_name", "No Data"))
    val temp = widgetData.getString("temp_display$suffix", widgetData.getString("temp_display", "--"))
    val wind = widgetData.getString("wind_display$suffix", widgetData.getString("wind_display", "--"))
    val precip = widgetData.getString("precip_display$suffix", widgetData.getString("precip_display", "0%"))
    val tide = widgetData.getString("tide_display$suffix", widgetData.getString("tide_display", "--"))
    val roughnessLabel = widgetData.getString("roughness_label$suffix", widgetData.getString("roughness_label", "--"))
    val roughnessIndex = widgetData.getString("roughness_index$suffix", widgetData.getString("roughness_index", "--"))
    val weatherIcon = widgetData.getString("weather_icon$suffix", widgetData.getString("weather_icon", "⛅"))
    // val tideIcon = widgetData.getString("tide_icon$suffix", widgetData.getString("tide_icon", "🌊")) // Deprecated
    val tideImagePath = widgetData.getString("tide_image$suffix", widgetData.getString("tide_image", null))
    
    // Robust Color Reading: Dart might save colors as Longs (unsigned 32-bit > MAX_INT), so we must handle both.
    val defaultColor = Color.parseColor("#334155")
    val roughnessColor = try {
        widgetData.getInt("roughness_color$suffix", widgetData.getInt("roughness_color", defaultColor))
    } catch (e: ClassCastException) {
        widgetData.getLong("roughness_color$suffix", widgetData.getLong("roughness_color", defaultColor.toLong())).toInt()
    }

    val timestamp = widgetData.getString("last_updated$suffix", widgetData.getString("last_updated", "Updated: --:--"))

    // Construct the RemoteViews object
    val views = RemoteViews(context.packageName, R.layout.widget_layout)
    
    views.setTextViewText(R.id.widget_location_name, location)
    views.setTextViewText(R.id.widget_weather_icon, weatherIcon)
    views.setTextViewText(R.id.widget_temp, temp)
    views.setTextViewText(R.id.widget_precip, "💧$precip")
    views.setTextViewText(R.id.widget_wind, wind)
    // views.setTextViewText(R.id.widget_tide_icon, tideIcon)
    
    Log.d("MarineWidget", "UpdateWidget: Loc=$location, TidePath=$tideImagePath")

    if (tideImagePath != null) {
        val imageFile = File(tideImagePath)
        Log.d("MarineWidget", "ImageFile exists: ${imageFile.exists()} at ${imageFile.absolutePath}")
        if (imageFile.exists()) {
             val bitmap = BitmapFactory.decodeFile(imageFile.absolutePath)
             views.setImageViewBitmap(R.id.widget_tide_image, bitmap)
        }
    }

    views.setTextViewText(R.id.widget_tide, tide)
    views.setTextViewText(R.id.widget_roughness_index, roughnessIndex)
    views.setTextViewText(R.id.widget_roughness, roughnessLabel)
    views.setTextViewText(R.id.widget_timestamp, timestamp)

    // Update roughness pill color
    // We can't set background tint directly on a shape drawable easily in RemoteViews API < 31 without complexity,
    // but typically setInt with "setColorFilter" or just replacing the drawable works.
    // For simplicity with RemoteViews, we often use `setInt(id, "setColorFilter", color)` for images, 
    // or we can try `setBackgroundColor` if the view allows, but for a shape it's tricky.
    // However, `setTint` on background might work on newer androids.
    // Let's try `setInt(R.id.widget_roughness, "setBackgroundColor", roughnessColor)` - this replaces the shape.
    // Better: use `setAppCompatBackgroundTint` or similar if using compat libs, but this is a widget.
    
    // Fallback: Just text color for now if background is hard, but let's try standard SetInt for background color filtering
    // Actually, creating a Bitmap or GradientDrawable programmatically is not easy in RemoteViews.
    // Simplest: `views.setInt(R.id.widget_roughness, "setBackgroundColor", roughnessColor)` will make it a square.
    // To keep rounded corners, we need to apply a color filter to the background drawable.
    // `views.setInt(R.id.widget_roughness, "setColorFilter", roughnessColor)` might apply to the text if it's a TextView.
    // It applies to the background if we target the background method, but TextView doesn't expose `getBackground().setColorFilter`.
    
    // Workaround: Use different drawables (green_pill, orange_pill) OR just use text color for roughness and keeps background static.
    // Let's try using `setInt(R.id.widget_roughness, "setBackgroundColor", roughnessColor)` and accept it might lose corners on some versions,
    // OR just use text color.
    // Let's stick to a static background for now to be safe and ensure the text is readable.
    // We'll set the TEXT color to the roughness color instead, and keep a dark background.
    // We'll set the background tint of the index pill manually if possible, or just text color
    // For now, let's set the text color of the label, and maybe the background of the index if we can.
    // simpler: set the text color of the Roughness LABEL to the color.
    views.setTextColor(R.id.widget_roughness, roughnessColor)
    
    // Also try to set the index pill background color (this might need setInt on background)
    // views.setInt(R.id.widget_roughness_index, "setColorFilter", roughnessColor) // might work if it's a shape
    // Instead, let's just color the index text too
    // views.setTextColor(R.id.widget_roughness_index, roughnessColor) 
    
    // Actually the user wants it like the app. App has colored circle. 
    // We are using a drawable 'roughness_pill'. 
    // Let's try to tint the background of the index pill.
    views.setInt(R.id.widget_roughness_index, "setBackgroundColor", roughnessColor)
    // And set text to white (already in XML)

    // Open App on Click
    val intent = Intent(context, MainActivity::class.java)
    val pendingIntent = PendingIntent.getActivity(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
    
    // Apply Theme
    val themeMode = widgetData.getInt("theme_mode", 0) // 0=System, 1=Light, 2=Dark
    if (themeMode != 0) {
        val isDark = themeMode == 2
        
        // Manual color overrides to follow app setting instead of system setting
        val bgColor = if (isDark) Color.parseColor("#1E293B") else Color.parseColor("#F8FAFC")
        val primaryColor = if (isDark) Color.parseColor("#F8FAFC") else Color.parseColor("#0F172A")
        val secondaryColor = if (isDark) Color.parseColor("#94A3B8") else Color.parseColor("#64748B")
        val tideColor = if (isDark) Color.parseColor("#4CC9F0") else Color.parseColor("#2563EB")
        val precipColor = if (isDark) Color.parseColor("#38BDF8") else Color.parseColor("#2563EB")
        val timestampColor = Color.parseColor("#64748B")
        val bgRes = if (isDark) R.drawable.widget_background_dark else R.drawable.widget_background_light

        views.setInt(R.id.widget_root, "setBackgroundResource", bgRes)
        views.setTextColor(R.id.widget_location_name, primaryColor)
        views.setTextColor(R.id.widget_weather_icon, primaryColor)
        views.setTextColor(R.id.widget_temp, primaryColor)
        views.setTextColor(R.id.widget_wind, secondaryColor)
        views.setTextColor(R.id.widget_precip, precipColor)
        views.setTextColor(R.id.widget_tide, tideColor)
        views.setTextColor(R.id.widget_timestamp, timestampColor)
    }

    // Instruct the widget manager to update the widget
    appWidgetManager.updateAppWidget(appWidgetId, views)
}

