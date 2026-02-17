defmodule DipguideBackendWeb.ShareController do
  use DipguideBackendWeb, :controller

  alias DipguideBackend.{Community, WeatherShare}

  def short_redirect(conn, %{"short_id" => short_id}) do
    case Community.get_post_by_short_id(short_id) do
      nil ->
        conn |> put_status(:not_found) |> text("Not found")

      post ->
        # Render the full share page (with OG meta tags) directly instead of
        # redirecting. WhatsApp's crawler often ignores 302 redirects when
        # scraping OG tags, so the preview image never appears.
        post(conn, %{"id" => post.id})
    end
  end

  def post(conn, %{"id" => id}) do
    case Community.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("Not found")

      post ->
        post_time = post.forecast_time || floor_to_hour(post.inserted_at)

        weather =
          case WeatherShare.get_hour_snapshot(post.lat, post.lon, post_time) do
            {:ok, w} -> w
            _ -> %{}
          end

        {image_url, image_content_type} =
          case post.images do
            [img | _] ->
              {DipguideBackendWeb.Endpoint.url() <> "/uploads/" <> img.file_key, img.content_type}

            _ ->
              {nil, nil}
          end

        share_url = DipguideBackendWeb.Endpoint.url() <> "/share/posts/" <> post.id

        # Use pre-generated static preview if it exists, otherwise fall back to dynamic
        og_image_url = static_preview_url("post_#{post.id}") ||
          DipguideBackendWeb.Endpoint.url() <> "/share/posts/" <> post.id <> "/preview.png"

        open_url = build_open_url(post, post_time)

        conn
        |> put_layout(false)
        |> put_root_layout(false)
        |> render(:post,
          post: post,
          post_time: post_time,
          weather: weather,
          image_url: image_url,
          og_image_url: og_image_url,
          image_content_type: image_content_type,
          share_url: share_url,
          open_url: open_url
        )
    end
  end

  def forecast(conn, params) do
    lat = parse_float(params["lat"], nil)
    lon = parse_float(params["lon"], nil)
    loc = params["loc"] || "Shared Location"
    comment = params["comment"]

    if is_nil(lat) or is_nil(lon) do
      conn
      |> put_status(:bad_request)
      |> text("Missing lat/lon")
    else
      ts = parse_int(params["ts"], DateTime.to_unix(DateTime.utc_now()))
      post_time = DateTime.from_unix!(ts) |> floor_to_hour()

      weather =
        case WeatherShare.get_hour_snapshot(lat, lon, post_time) do
          {:ok, w} -> w
          _ -> %{}
        end

      pseudo_post = %{
        id: "forecast",
        location_name: loc,
        lat: lat,
        lon: lon,
        comment: comment
      }

      share_url =
        DipguideBackendWeb.Endpoint.url() <> "/share/forecast?" <> URI.encode_query(params)

      # Use pre-generated static preview if it exists, otherwise fall back to dynamic
      forecast_key = "forecast_#{:erlang.phash2({lat, lon, loc, ts})}"
      preview_url = static_preview_url(forecast_key) ||
        DipguideBackendWeb.Endpoint.url() <>
          "/share/forecast/preview.png?" <> URI.encode_query(params)

      open_url = build_forecast_open_url(lat, lon, loc, post_time)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:post,
        post: pseudo_post,
        post_time: post_time,
        weather: weather,
        image_url: nil,
        og_image_url: preview_url,
        image_content_type: nil,
        share_url: share_url,
        open_url: open_url
      )
    end
  end

  def post_preview(conn, %{"id" => id}) do
    case Community.get_post(id) do
      nil ->
        send_resp(conn, 404, "not found")

      post ->
        post_time = post.forecast_time || floor_to_hour(post.inserted_at)

        weather =
          case WeatherShare.get_hour_snapshot(post.lat, post.lon, post_time) do
            {:ok, w} -> w
            _ -> %{}
          end

        photo_data_uri = read_photo_data_uri(post.images)
        svg = build_preview_svg(post.location_name, post_time, weather, post.comment, photo_data_uri)
        serve_png_preview(conn, svg)
    end
  end

  def forecast_preview(conn, params) do
    lat = parse_float(params["lat"], nil)
    lon = parse_float(params["lon"], nil)
    loc = params["loc"] || "Shared Location"
    comment = params["comment"]

    if is_nil(lat) or is_nil(lon) do
      send_resp(conn, 400, "missing lat/lon")
    else
      ts = parse_int(params["ts"], DateTime.to_unix(DateTime.utc_now()))
      post_time = DateTime.from_unix!(ts) |> floor_to_hour()

      weather =
        case WeatherShare.get_hour_snapshot(lat, lon, post_time) do
          {:ok, w} -> w
          _ -> %{}
        end

      svg = build_preview_svg(loc, post_time, weather, comment)
      serve_png_preview(conn, svg)
    end
  end

  defp build_open_url(post, %DateTime{} = post_time) do
    ts = DateTime.to_unix(post_time)

    v =
      "#{Float.round(post.lat, 4)},#{Float.round(post.lon, 4)}," <>
        "#{URI.encode(post.location_name)},#{ts}"

    base = DipguideBackendWeb.Endpoint.url()
    base <> "/?v=#{v}"
  end

  defp build_forecast_open_url(lat, lon, loc, %DateTime{} = post_time) do
    ts = DateTime.to_unix(post_time)
    v = "#{Float.round(lat, 4)},#{Float.round(lon, 4)},#{URI.encode(loc)},#{ts}"
    base = DipguideBackendWeb.Endpoint.url()
    base <> "/?v=#{v}"
  end

  defp parse_float(nil, default), do: default
  defp parse_float(v, _default) when is_number(v), do: v * 1.0

  defp parse_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(v, _default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> default
    end
  end

  defp floor_to_hour(%DateTime{} = dt) do
    ndt = DateTime.to_naive(dt)
    ndt = %{ndt | minute: 0, second: 0, microsecond: {0, 0}}
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp static_preview_url(key) do
    upload_dir =
      Application.get_env(:dipguide_backend, :upload_dir) || System.get_env("UPLOAD_DIR")

    if upload_dir do
      path = Path.join([upload_dir, "previews", "#{key}.png"])
      if File.exists?(path) do
        DipguideBackendWeb.Endpoint.url() <> "/uploads/previews/#{key}.png"
      end
    end
  end

  def read_photo_data_uri([]), do: nil
  def read_photo_data_uri(nil), do: nil

  def read_photo_data_uri([img | _]) do
    upload_dir =
      Application.get_env(:dipguide_backend, :upload_dir) || System.get_env("UPLOAD_DIR")

    with dir when is_binary(dir) <- upload_dir,
         path = Path.join(dir, img.file_key),
         {:ok, %{size: size}} when size < 3_000_000 <- File.stat(path),
         {:ok, data} <- File.read(path) do
      # Resize image to reduce final PNG size (WhatsApp has 300KB limit)
      # Use ImageMagick/mogrify to resize to max 400px width
      resized_path = Path.join(System.tmp_dir!(), "resized_#{:erlang.unique_integer([:positive])}.jpg")
      
      case System.cmd("convert", [path, "-resize", "400x400>", "-quality", "60", resized_path], stderr_to_stdout: true) do
        {_, 0} ->
          case File.read(resized_path) do
            {:ok, resized_data} ->
              File.rm(resized_path)
              "data:image/jpeg;base64,#{Base.encode64(resized_data)}"
            _ ->
              File.rm(resized_path)
              nil
          end
        _ ->
          # Fallback to original if ImageMagick not available
          ct = img.content_type || "image/jpeg"
          "data:#{ct};base64,#{Base.encode64(data)}"
      end
    else
      _ -> nil
    end
  end

  def build_preview_svg(location_name, %DateTime{} = post_time, weather, comment, photo_data_uri \\ nil) do
    alias DipguideBackendWeb.ShareView
    time = ShareView.time_label(post_time)
    temp = ShareView.format_temp(weather)
    wind = ShareView.format_wind_compact(weather)
    rain = ShareView.format_rain_compact(weather)
    wave_h = ShareView.format_wave_height(weather)
    wave_p = ShareView.format_wave_period(weather)
    rough = ShareView.roughness_pct(weather)
    rough_col = ShareView.roughness_color(weather)
    wave_arrow = ShareView.wave_arrow(weather)
    date_str = Calendar.strftime(post_time, "%a %d %b")
    comment = if is_binary(comment), do: String.slice(comment, 0, 120), else: ""
    
    # Get rain percentage for weather icon
    rain_pct = Map.get(weather, :rain_pct, 0) || 0

    if photo_data_uri do
      build_composite_svg(location_name, time, date_str, temp, wind, rain, wave_h, wave_p, wave_arrow, rough, rough_col, comment, photo_data_uri, rain_pct)
    else
      build_weather_only_svg(location_name, time, date_str, temp, wind, rain, wave_h, wave_p, wave_arrow, rough, rough_col, comment, rain_pct)
    end
  end

  defp build_composite_svg(loc, time, date, temp, wind, rain, wave_h, wave_p, wave_arr, rough, rough_col, _comment, photo_uri, rain_pct) do
    # Generate wavy lines based on roughness percentage
    wave_lines = generate_wave_lines(rough, rough_col)
    # Generate weather icon based on rain percentage
    weather_icon = generate_weather_icon(rain_pct)
    # Generate tide icon (filled wave container)
    tide_icon = generate_tide_icon()
    
    """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1200" height="900">
      <defs>
        <clipPath id="photoClip"><rect x="0" y="340" width="1200" height="520" rx="0"/></clipPath>
      </defs>
      <rect width="1200" height="900" fill="#0f172a"/>

      <!-- Header: location + time/date -->
      <text x="40" y="62" font-family="Arial, sans-serif" font-size="52" font-weight="700" fill="#f8fafc">#{escape(loc)}</text>
      <text x="40" y="98" font-family="Arial, sans-serif" font-size="26" fill="#64748b">#{escape(date)} #{escape(time)}</text>

      <!-- Weather row -->
      <rect x="24" y="116" width="1152" height="200" rx="16" fill="#1e293b"/>
      <rect x="24" y="116" width="7" height="200" rx="3" fill="#3b82f6"/>

      <!-- Temperature with weather icon -->
      <text x="80" y="155" font-family="Arial, sans-serif" font-size="20" fill="#94a3b8">TEMP</text>
      #{weather_icon}
      <text x="160" y="230" font-family="Arial, sans-serif" font-size="68" font-weight="800" fill="#f8fafc">#{escape(temp)}</text>
      <text x="160" y="280" font-family="Arial, sans-serif" font-size="22" fill="#94a3b8">#{escape(wind)}</text>

      <!-- Rain -->
      <text x="420" y="155" font-family="Arial, sans-serif" font-size="20" fill="#94a3b8">RAIN</text>
      <text x="420" y="230" font-family="Arial, sans-serif" font-size="48" font-weight="700" fill="#38bdf8">#{escape(rain)}</text>

      <!-- Tide with tide icon -->
      <text x="600" y="155" font-family="Arial, sans-serif" font-size="20" fill="#94a3b8">TIDE</text>
      #{tide_icon}
      <text x="720" y="230" font-family="Arial, sans-serif" font-size="46" font-weight="800" fill="#a78bfa">#{escape(wave_h)}</text>
      <text x="900" y="230" font-family="Arial, sans-serif" font-size="38" fill="#a78bfa">#{escape(wave_arr)}</text>
      <text x="720" y="280" font-family="Arial, sans-serif" font-size="22" fill="#94a3b8">#{escape(wave_p)}</text>

      <!-- Roughness badge with wavy lines -->
      <rect x="1000" y="144" width="150" height="130" rx="20" fill="#{rough_col}22"/>
      <text x="1075" y="175" font-family="Arial, sans-serif" font-size="20" fill="#94a3b8" text-anchor="middle">ROUGH</text>
      #{wave_lines}

      <!-- Photo (below weather) -->
      <image x="0" y="340" width="1200" height="520" href="#{photo_uri}" preserveAspectRatio="xMidYMid slice" clip-path="url(#photoClip)"/>
    </svg>
    """
  end

  defp build_weather_only_svg(loc, time, date, temp, wind, rain, wave_h, wave_p, wave_arr, rough, rough_col, comment, rain_pct) do
    # Generate wavy lines based on roughness percentage (smaller version)
    wave_lines = generate_wave_lines_small(rough, rough_col)
    # Generate weather icon based on rain percentage
    weather_icon = generate_weather_icon_small(rain_pct)
    # Generate tide icon (filled wave container)
    tide_icon = generate_tide_icon_small()
    
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
      <rect width="1200" height="630" fill="#0f172a"/>

      <!-- Header: location + time/date -->
      <text x="40" y="62" font-family="Arial, sans-serif" font-size="52" font-weight="700" fill="#f8fafc">#{escape(loc)}</text>
      <text x="40" y="98" font-family="Arial, sans-serif" font-size="26" fill="#64748b">#{escape(date)} #{escape(time)}</text>

      <!-- Weather row -->
      <rect x="24" y="116" width="1152" height="180" rx="16" fill="#1e293b"/>
      <rect x="24" y="116" width="7" height="180" rx="3" fill="#3b82f6"/>

      <!-- Temperature with weather icon -->
      <text x="80" y="150" font-family="Arial, sans-serif" font-size="18" fill="#94a3b8">TEMP</text>
      #{weather_icon}
      <text x="150" y="215" font-family="Arial, sans-serif" font-size="56" font-weight="800" fill="#f8fafc">#{escape(temp)}</text>
      <text x="150" y="260" font-family="Arial, sans-serif" font-size="20" fill="#94a3b8">#{escape(wind)}</text>

      <!-- Rain -->
      <text x="380" y="150" font-family="Arial, sans-serif" font-size="18" fill="#94a3b8">RAIN</text>
      <text x="380" y="215" font-family="Arial, sans-serif" font-size="42" font-weight="700" fill="#38bdf8">#{escape(rain)}</text>

      <!-- Tide with tide icon -->
      <text x="540" y="150" font-family="Arial, sans-serif" font-size="18" fill="#94a3b8">TIDE</text>
      #{tide_icon}
      <text x="640" y="215" font-family="Arial, sans-serif" font-size="38" font-weight="800" fill="#a78bfa">#{escape(wave_h)}</text>
      <text x="800" y="215" font-family="Arial, sans-serif" font-size="32" fill="#a78bfa">#{escape(wave_arr)}</text>
      <text x="640" y="260" font-family="Arial, sans-serif" font-size="20" fill="#94a3b8">#{escape(wave_p)}</text>

      <!-- Roughness badge with wavy lines -->
      <rect x="920" y="134" width="120" height="120" rx="18" fill="#{rough_col}22"/>
      <text x="980" y="165" font-family="Arial, sans-serif" font-size="18" fill="#94a3b8" text-anchor="middle">ROUGH</text>
      #{wave_lines}

      <!-- Comment -->
      <text x="60" y="360" font-family="Arial, sans-serif" font-size="32" fill="#e2e8f0">#{escape(comment)}</text>

      <!-- Large branding area -->
      <text x="600" y="480" font-family="Arial, sans-serif" font-size="80" font-weight="800" fill="#1e293b" text-anchor="middle">DIP REPORT</text>
      <text x="600" y="550" font-family="Arial, sans-serif" font-size="30" fill="#334155" text-anchor="middle">Open sea swimming conditions</text>
    </svg>
    """
  end

  defp serve_png_preview(conn, svg) do
    case svg_to_png(svg) do
      {:ok, png_data} ->
        conn
        |> put_resp_content_type("image/png", nil)
        |> put_resp_header("cache-control", "public, max-age=300")
        |> send_resp(200, png_data)

      :error ->
        # Fallback to SVG if rsvg-convert is not available
        conn |> put_resp_content_type("image/svg+xml", nil) |> send_resp(200, svg)
    end
  end

  defp svg_to_png(svg) do
    tmp_svg = Path.join(System.tmp_dir!(), "preview_#{:erlang.unique_integer([:positive])}.svg")
    tmp_png = Path.join(System.tmp_dir!(), "preview_#{:erlang.unique_integer([:positive])}.png")

    try do
      File.write!(tmp_svg, svg)

      case System.cmd("rsvg-convert", ["-w", "1200", "-o", tmp_png, tmp_svg],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          {:ok, File.read!(tmp_png)}

        _ ->
          :error
      end
    rescue
      _ -> :error
    after
      File.rm(tmp_svg)
      File.rm(tmp_png)
    end
  end

  # Generate weather icon (sun/cloud/rain) based on rain percentage
  # Large version for composite (photo) SVG — ~50px icons
  defp generate_weather_icon(rain_pct) when is_number(rain_pct) do
    cond do
      rain_pct > 60 ->
        # Rain icon - cloud with rain drops
        """
        <g transform="translate(100, 210)">
          <circle cx="0" cy="-8" r="18" fill="#94a3b8"/>
          <circle cx="22" cy="-12" r="22" fill="#94a3b8"/>
          <circle cx="-18" cy="-10" r="15" fill="#94a3b8"/>
          <rect x="-22" y="-2" width="60" height="8" rx="4" fill="#94a3b8"/>
          <line x1="-12" y1="14" x2="-16" y2="30" stroke="#38bdf8" stroke-width="3" stroke-linecap="round"/>
          <line x1="2" y1="16" x2="-2" y2="32" stroke="#38bdf8" stroke-width="3" stroke-linecap="round"/>
          <line x1="16" y1="14" x2="12" y2="30" stroke="#38bdf8" stroke-width="3" stroke-linecap="round"/>
          <line x1="30" y1="16" x2="26" y2="32" stroke="#38bdf8" stroke-width="3" stroke-linecap="round"/>
        </g>
        """
      rain_pct > 30 ->
        # Partly cloudy - sun with cloud overlay
        """
        <g transform="translate(100, 210)">
          <circle cx="-6" cy="-16" r="18" fill="#fbbf24"/>
          <line x1="-6" y1="-42" x2="-6" y2="-38" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="-6" y1="8" x2="-6" y2="4" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="-32" y1="-16" x2="-28" y2="-16" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="20" y1="-16" x2="16" y2="-16" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <circle cx="12" cy="4" r="16" fill="#cbd5e1"/>
          <circle cx="30" cy="0" r="20" fill="#cbd5e1"/>
          <circle cx="-4" cy="2" r="14" fill="#cbd5e1"/>
          <rect x="-10" y="8" width="52" height="8" rx="4" fill="#cbd5e1"/>
        </g>
        """
      true ->
        # Sunny - sun with rays
        """
        <g transform="translate(100, 210)">
          <circle cx="0" cy="0" r="20" fill="#fbbf24"/>
          <line x1="0" y1="-30" x2="0" y2="-38" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="0" y1="30" x2="0" y2="38" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="-30" y1="0" x2="-38" y2="0" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="30" y1="0" x2="38" y2="0" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="-21" y1="-21" x2="-27" y2="-27" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="21" y1="-21" x2="27" y2="-27" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="-21" y1="21" x2="-27" y2="27" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
          <line x1="21" y1="21" x2="27" y2="27" stroke="#fbbf24" stroke-width="3" stroke-linecap="round"/>
        </g>
        """
    end
  end
  defp generate_weather_icon(_), do: generate_weather_icon(0)
  
  # Small version for weather-only SVG — ~40px icons
  defp generate_weather_icon_small(rain_pct) when is_number(rain_pct) do
    cond do
      rain_pct > 60 ->
        """
        <g transform="translate(90, 195)">
          <circle cx="0" cy="-6" r="14" fill="#94a3b8"/>
          <circle cx="18" cy="-10" r="18" fill="#94a3b8"/>
          <circle cx="-14" cy="-8" r="12" fill="#94a3b8"/>
          <rect x="-18" y="-2" width="48" height="6" rx="3" fill="#94a3b8"/>
          <line x1="-10" y1="10" x2="-13" y2="24" stroke="#38bdf8" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="2" y1="12" x2="-1" y2="26" stroke="#38bdf8" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="14" y1="10" x2="11" y2="24" stroke="#38bdf8" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="26" y1="12" x2="23" y2="26" stroke="#38bdf8" stroke-width="2.5" stroke-linecap="round"/>
        </g>
        """
      rain_pct > 30 ->
        """
        <g transform="translate(90, 195)">
          <circle cx="-4" cy="-14" r="14" fill="#fbbf24"/>
          <line x1="-4" y1="-34" x2="-4" y2="-30" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="-4" y1="6" x2="-4" y2="2" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="-24" y1="-14" x2="-20" y2="-14" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="16" y1="-14" x2="12" y2="-14" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <circle cx="10" cy="2" r="13" fill="#cbd5e1"/>
          <circle cx="26" cy="-2" r="16" fill="#cbd5e1"/>
          <circle cx="-4" cy="0" r="11" fill="#cbd5e1"/>
          <rect x="-8" y="6" width="44" height="6" rx="3" fill="#cbd5e1"/>
        </g>
        """
      true ->
        """
        <g transform="translate(90, 195)">
          <circle cx="0" cy="0" r="16" fill="#fbbf24"/>
          <line x1="0" y1="-24" x2="0" y2="-30" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="0" y1="24" x2="0" y2="30" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="-24" y1="0" x2="-30" y2="0" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="24" y1="0" x2="30" y2="0" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="-17" y1="-17" x2="-21" y2="-21" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="17" y1="-17" x2="21" y2="-21" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="-17" y1="17" x2="-21" y2="21" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
          <line x1="17" y1="17" x2="21" y2="21" stroke="#fbbf24" stroke-width="2.5" stroke-linecap="round"/>
        </g>
        """
    end
  end
  defp generate_weather_icon_small(_), do: generate_weather_icon_small(0)
  
  # Generate tide icon (filled wave container like the app)
  # Large version for composite (photo) SVG — ~70px icon
  defp generate_tide_icon() do
    """
    <g transform="translate(640, 210)">
      <rect x="-38" y="-38" width="76" height="76" rx="10" fill="#a78bfa" fill-opacity="0.1" stroke="#a78bfa" stroke-opacity="0.3" stroke-width="2"/>
      <path d="M -38 10 Q -24 -8, -10 10 T 18 10 T 38 10 L 38 38 L -38 38 Z" fill="#a78bfa" fill-opacity="0.5"/>
      <path d="M -38 10 Q -24 -8, -10 10 T 18 10 T 38 10" fill="none" stroke="#a78bfa" stroke-width="3" stroke-linecap="round"/>
      <path d="M -38 -6 Q -24 -24, -10 -6 T 18 -6 T 38 -6" fill="none" stroke="#a78bfa" stroke-width="2" stroke-opacity="0.4" stroke-linecap="round"/>
    </g>
    """
  end

  # Small version for weather-only SVG — ~60px icon
  defp generate_tide_icon_small() do
    """
    <g transform="translate(565, 195)">
      <rect x="-30" y="-30" width="60" height="60" rx="8" fill="#a78bfa" fill-opacity="0.1" stroke="#a78bfa" stroke-opacity="0.3" stroke-width="2"/>
      <path d="M -30 8 Q -18 -8, -6 8 T 14 8 T 30 8 L 30 30 L -30 30 Z" fill="#a78bfa" fill-opacity="0.5"/>
      <path d="M -30 8 Q -18 -8, -6 8 T 14 8 T 30 8" fill="none" stroke="#a78bfa" stroke-width="2.5" stroke-linecap="round"/>
      <path d="M -30 -6 Q -18 -20, -6 -6 T 14 -6 T 30 -6" fill="none" stroke="#a78bfa" stroke-width="1.5" stroke-opacity="0.4" stroke-linecap="round"/>
    </g>
    """
  end

  defp generate_wave_lines(rough_str, color) do
    # Parse roughness percentage
    rough = case Integer.parse(to_string(rough_str)) do
      {num, _} -> num
      :error -> 50
    end
    
    # Determine number of waves based on roughness (1-4 waves)
    wave_count = cond do
      rough <= 25 -> 1
      rough <= 50 -> 2
      rough <= 75 -> 3
      true -> 4
    end
    
    # Generate SVG paths for wavy lines (for composite - larger badge)
    # Center the waves in the badge at x=1075, starting at y=205
    Enum.map_join(0..(wave_count - 1), "\n", fn i ->
      y_offset = 205 + (i * 15)
      # Generate sine wave path
      points = for x <- 0..100//5 do
        # Map x from 0-100 to actual badge width (centered around 1075, width ~80px)
        actual_x = 1035 + x * 0.8
        # Sine wave: amplitude=2, frequency adjusted for width
        y = y_offset + 2 * :math.sin(x * 0.15)
        "#{actual_x},#{y}"
      end
      
      path_data = "M " <> Enum.join(points, " L ")
      ~s(<path d="#{path_data}" stroke="#{color}" stroke-width="2" fill="none" stroke-linecap="round"/>)
    end)
  end
  
  defp generate_wave_lines_small(rough_str, color) do
    # Parse roughness percentage
    rough = case Integer.parse(to_string(rough_str)) do
      {num, _} -> num
      :error -> 50
    end
    
    # Determine number of waves based on roughness (1-4 waves)
    wave_count = cond do
      rough <= 25 -> 1
      rough <= 50 -> 2
      rough <= 75 -> 3
      true -> 4
    end
    
    # Generate SVG paths for wavy lines (for weather-only - smaller badge)
    # Center the waves in the badge at x=980, starting at y=195
    Enum.map_join(0..(wave_count - 1), "\n", fn i ->
      y_offset = 195 + (i * 12)
      # Generate sine wave path
      points = for x <- 0..100//5 do
        # Map x from 0-100 to actual badge width (centered around 980, width ~70px)
        actual_x = 945 + x * 0.7
        # Sine wave: amplitude=2, frequency adjusted for width
        y = y_offset + 2 * :math.sin(x * 0.15)
        "#{actual_x},#{y}"
      end
      
      path_data = "M " <> Enum.join(points, " L ")
      ~s(<path d="#{path_data}" stroke="#{color}" stroke-width="2" fill="none" stroke-linecap="round"/>)
    end)
  end

  defp escape(nil), do: ""

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
