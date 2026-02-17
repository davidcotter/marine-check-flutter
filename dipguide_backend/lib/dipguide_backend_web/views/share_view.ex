defmodule DipguideBackendWeb.ShareView do
  @moduledoc false

  def og_title(post, _post_time, _weather) do
    post.location_name
  end

  def description(post, _post_time, _weather) do
    if post.comment && String.trim(post.comment) != "" do
      post.comment
    else
      "Swim conditions at #{post.location_name}"
    end
  end

  def time_label(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:00")

  # --- Weather icon (WMO-like, but we only have temp/wind/rain) ---
  def weather_icon(w) do
    rain = Map.get(w, :rain_pct, 0)
    wind = Map.get(w, :wind_kph, 0)

    cond do
      is_number(rain) and rain > 60 -> "🌧️"
      is_number(rain) and rain > 30 -> "🌦️"
      is_number(wind) and wind > 40 -> "💨"
      true -> "⛅"
    end
  end

  # --- Temperature ---
  def format_temp(w) do
    t = Map.get(w, :temperature_c)
    if is_number(t), do: "#{Float.round(t * 1.0, 1)}°C", else: "—"
  end

  # --- Wind ---
  def format_wind(w) do
    s = Map.get(w, :wind_kph)
    d = Map.get(w, :wind_dir)

    cond do
      is_number(s) && is_number(d) -> "#{round(s)} km/h @ #{round(d)}°"
      is_number(s) -> "#{round(s)} km/h"
      true -> "—"
    end
  end

  def format_wind_compact(w) do
    s = Map.get(w, :wind_kph)
    if is_number(s), do: "#{round(s)} km/h", else: "—"
  end

  # --- Waves ---
  def format_waves(w) do
    h = Map.get(w, :wave_m)
    p = Map.get(w, :wave_s)

    cond do
      is_number(h) && is_number(p) -> "#{Float.round(h * 1.0, 1)} m · #{round(p)}s"
      is_number(h) -> "#{Float.round(h * 1.0, 1)} m"
      true -> "—"
    end
  end

  def format_wave_height(w) do
    h = Map.get(w, :wave_m)
    if is_number(h), do: "#{Float.round(h * 1.0, 2)}m", else: "—"
  end

  def format_wave_period(w) do
    p = Map.get(w, :wave_s)
    if is_number(p), do: "#{round(p)}s", else: ""
  end

  def wave_arrow(w) do
    d = Map.get(w, :wave_dir)
    if is_number(d), do: dir_to_arrow(d), else: ""
  end

  # --- Rain ---
  def format_rain(w) do
    r = Map.get(w, :rain_pct)
    if is_number(r), do: "#{round(r)}% rain", else: "—"
  end

  def format_rain_compact(w) do
    r = Map.get(w, :rain_pct)
    if is_number(r), do: "#{round(r)}%", else: "—"
  end

  # --- Roughness (estimated from wave height & wind) ---
  def roughness_pct(w) do
    "#{roughness_index(w)}%"
  end

  def roughness_color(w) do
    idx = roughness_index(w)

    cond do
      idx >= 70 -> "#ef4444"
      idx >= 45 -> "#f97316"
      idx >= 20 -> "#3b82f6"
      true -> "#22c55e"
    end
  end

  def roughness_bg(w) do
    idx = roughness_index(w)

    cond do
      idx >= 70 -> "rgba(239,68,68,0.15)"
      idx >= 45 -> "rgba(249,115,22,0.15)"
      idx >= 20 -> "rgba(59,130,246,0.12)"
      true -> "rgba(34,197,94,0.12)"
    end
  end

  def roughness_icon(w) do
    idx = roughness_index(w)

    cond do
      idx >= 70 -> "🌊"
      idx >= 45 -> "🌊"
      idx >= 20 -> "〰️"
      true -> "〰️"
    end
  end

  # Simplified roughness calculation matching the Flutter app's logic
  defp roughness_index(w) do
    wave = Map.get(w, :wave_m, 0) || 0
    wind = Map.get(w, :wind_kph, 0) || 0

    wave_score = min(wave / 2.0 * 60, 60)
    wind_score = min(wind / 50.0 * 40, 40)
    idx = round(wave_score + wind_score)
    min(idx, 100)
  end

  # Direction degrees → arrow character
  defp dir_to_arrow(deg) when is_number(deg) do
    d = rem(round(deg), 360)

    cond do
      d >= 337 or d < 22 -> "↓"
      d < 67 -> "↙"
      d < 112 -> "←"
      d < 157 -> "↖"
      d < 202 -> "↑"
      d < 247 -> "↗"
      d < 292 -> "→"
      true -> "↘"
    end
  end

  defp dir_to_arrow(_), do: ""
end
