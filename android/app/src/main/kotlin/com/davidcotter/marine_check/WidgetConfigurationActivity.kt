package com.davidcotter.marine_check

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.Button
import org.json.JSONArray
import org.json.JSONObject

class WidgetConfigurationActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Set the result to CANCELED. This will cause the widget host to cancel
        // out of the widget placement if the user presses the back button.
        setResult(RESULT_CANCELED)

        setContentView(R.layout.widget_config)

        // Find the widget id from the intent.
        val intent = intent
        val extras = intent.extras
        if (extras != null) {
            appWidgetId = extras.getInt(
                AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID
            )
        }

        // If this activity was started with an invalid widget ID, finish with an error.
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val locationListView = findViewById<ListView>(R.id.location_list)
        val cancelButton = findViewById<Button>(R.id.cancel_button)
        val progressBar = findViewById<android.widget.ProgressBar>(R.id.loading_progress)

        // Load locations from Flutter SharedPreferences in background
        progressBar.visibility = android.view.View.VISIBLE
        locationListView.visibility = android.view.View.GONE

        Thread {
            val startTime = System.currentTimeMillis()
            val locations = loadLocations()
            val displayNames = mutableListOf("Follow App Selection")
            displayNames.addAll(locations.map { it.name })
            
            val duration = System.currentTimeMillis() - startTime
            android.util.Log.d("WidgetConfig", "Loaded ${locations.size} locations in ${duration}ms")

            runOnUiThread {
                progressBar.visibility = android.view.View.GONE
                locationListView.visibility = android.view.View.VISIBLE
                
                val adapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, displayNames)
                locationListView.adapter = adapter
                
                locationListView.setOnItemClickListener { _, _, position, _ ->
                    val selectedLocationId = if (position == 0) "follow_app" else locations[position - 1].id
                    saveLocationId(this, appWidgetId, selectedLocationId)

                    // Make sure we pass back the original appWidgetId
                    val resultValue = Intent()
                    resultValue.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    setResult(RESULT_OK, resultValue)
                    
                    // Force an update
                    val appWidgetManager = AppWidgetManager.getInstance(this)
                    updateAppWidget(this, appWidgetManager, appWidgetId)
                    
                    finish()
                }
            }
        }.start()

        cancelButton.setOnClickListener {
            finish()
        }
    }

    private data class LocationItem(val id: String, val name: String)

    private fun loadLocations(): List<LocationItem> {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val data = prefs.getString("flutter.saved_locations", null) ?: return emptyList()
        
        return try {
            val jsonArray = JSONArray(data)
            val list = mutableListOf<LocationItem>()
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                list.add(LocationItem(obj.getString("id"), obj.getString("name")))
            }
            list
        } catch (e: Exception) {
            emptyList()
        }
    }

    companion object {
        private const val PREFS_NAME = "com.davidcotter.marine_check.WidgetPrefs"
        private const val PREF_PREFIX_KEY = "appwidget_"

        fun saveLocationId(context: Context, appWidgetId: Int, locationId: String) {
            val prefs = context.getSharedPreferences(PREFS_NAME, 0).edit()
            prefs.putString(PREF_PREFIX_KEY + appWidgetId, locationId)
            prefs.apply()
        }

        fun loadLocationId(context: Context, appWidgetId: Int): String? {
            val prefs = context.getSharedPreferences(PREFS_NAME, 0)
            return prefs.getString(PREF_PREFIX_KEY + appWidgetId, null)
        }

        fun deleteLocationId(context: Context, appWidgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, 0).edit()
            prefs.remove(PREF_PREFIX_KEY + appWidgetId)
            prefs.apply()
        }
    }
}
