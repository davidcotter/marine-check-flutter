defmodule DipguideBackendWeb.AppLive.Home do
  use DipguideBackendWeb, :live_view

  alias DipguideBackend.Community

  @default_locations [
    %{id: "forty_foot", name: "Forty Foot", lat: 53.2837, lon: -6.1159},
    %{id: "tramore", name: "Tramore", lat: 52.1601, lon: -7.1478},
    %{id: "sandycove", name: "Sandycove", lat: 53.2837, lon: -6.1159},
    %{id: "portmarnock", name: "Portmarnock", lat: 53.4167, lon: -6.1333}
  ]

  @impl true
  def mount(params, _session, socket) do
    location = parse_location_param(params)

    socket =
      socket
      |> assign(:page_title, "Dip Report — Sea Swimming Conditions Ireland")
      |> assign(:page_description, "Real-time coastal forecasts for Irish sea swimmers. Wave heights, tide times, wind speed, sea temperature, and the Roughness Index for the Forty Foot, Tramore, Sandycove and more.")
      |> assign(:locations, @default_locations)
      |> assign(:selected_location, location || hd(@default_locations))
      |> assign(:forecasts, [])
      |> assign(:days, [])
      |> assign(:selected_day_index, 0)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:last_updated, nil)
      |> assign(:active_tab, :forecast)
      |> assign(:posts, [])
      |> assign(:posts_loading, false)
      |> assign(:show_compose, false)
      |> assign(:compose_comment, "")
      |> assign(:compose_location_id, nil)
      |> assign(:compose_error, nil)
      |> assign(:compose_uploading, false)
      |> assign(:deep_link_message, params["message"])
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    # Fetch on dead render too so crawlers and first paint get real content
    resolved_loc = location || hd(@default_locations)
    socket =
      case fetch_forecast(resolved_loc.lat, resolved_loc.lon) do
        {:ok, days, last_updated} ->
          today_idx = find_today_index(days)
          socket
          |> assign(:days, days)
          |> assign(:selected_day_index, today_idx)
          |> assign(:loading, false)
          |> assign(:last_updated, last_updated)
        {:error, _} ->
          assign(socket, :loading, false)
      end

    if connected?(socket) do
      send(self(), :load_forecast)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = case params["tab"] do
      "posts" -> :posts
      _ -> :forecast
    end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_info(:load_forecast, socket) do
    loc = socket.assigns.selected_location
    case fetch_forecast(loc.lat, loc.lon) do
      {:ok, days, last_updated} ->
        today_idx = find_today_index(days)
        {:noreply,
         socket
         |> assign(:days, days)
         |> assign(:selected_day_index, today_idx)
         |> assign(:loading, false)
         |> assign(:last_updated, last_updated)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Failed to load forecast: #{reason}")}
    end
  end

  def handle_info(:load_posts, socket) do
    loc = socket.assigns.selected_location
    socket = assign(socket, :posts_loading, true)

    results = Community.list_public_nearby(loc.lat, loc.lon, radius_km: 50.0, limit: 30)
    posts = Enum.map(results, fn %{post: p, distance_km: d} ->
      Map.put(p, :distance_km, d)
    end)

    {:noreply,
     socket
     |> assign(:posts, posts)
     |> assign(:posts_loading, false)}
  end

  @impl true
  def handle_event("select_location", %{"id" => id}, socket) do
    loc = Enum.find(socket.assigns.locations, &(&1.id == id))
    if loc do
      socket =
        socket
        |> assign(:selected_location, loc)
        |> assign(:loading, true)
        |> assign(:forecasts, [])
        |> assign(:days, [])
        |> assign(:error, nil)
      send(self(), :load_forecast)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prev_day", _, socket) do
    idx = max(socket.assigns.selected_day_index - 1, 0)
    {:noreply, assign(socket, :selected_day_index, idx)}
  end

  def handle_event("next_day", _, socket) do
    max_idx = length(socket.assigns.days) - 1
    idx = min(socket.assigns.selected_day_index + 1, max_idx)
    {:noreply, assign(socket, :selected_day_index, idx)}
  end

  def handle_event("jump_today", _, socket) do
    idx = find_today_index(socket.assigns.days)
    {:noreply, assign(socket, :selected_day_index, idx)}
  end

  def handle_event("refresh", _, socket) do
    socket = assign(socket, :loading, true)
    send(self(), :load_forecast)
    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom = if tab == "posts", do: :posts, else: :forecast
    socket = assign(socket, :active_tab, tab_atom)
    if tab_atom == :posts && socket.assigns.posts == [] do
      send(self(), :load_posts)
    end
    {:noreply, socket}
  end

  def handle_event("open_compose", _, socket) do
    if socket.assigns.current_scope do
      {:noreply, assign(socket, :show_compose, true)}
    else
      {:noreply, push_navigate(socket, to: ~p"/html/login")}
    end
  end

  def handle_event("close_compose", _, socket) do
    {:noreply,
     socket
     |> assign(:show_compose, false)
     |> assign(:compose_comment, "")
     |> assign(:compose_error, nil)
     |> cancel_upload(:photo, :all)}
  end

  def handle_event("update_compose_comment", %{"value" => val}, socket) do
    {:noreply, assign(socket, :compose_comment, val)}
  end

  def handle_event("submit_post", _params, socket) do
    scope = socket.assigns.current_scope
    unless scope do
      {:noreply, push_navigate(socket, to: ~p"/html/login")}
    else
      loc = socket.assigns.selected_location

      uploaded =
        consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
          {:ok, {path, entry.client_name, entry.client_type}}
        end)

      case uploaded do
        [{path, filename, content_type}] ->
          upload = %Plug.Upload{
            path: path,
            filename: filename,
            content_type: content_type
          }

          comment = String.trim(socket.assigns.compose_comment)
          comment = if comment == "", do: nil, else: comment

          attrs = %{
            "lat" => loc.lat,
            "lon" => loc.lon,
            "location_name" => loc.name,
            "comment" => comment,
            "visibility" => "public"
          }

          case Community.create_post(scope, attrs, upload) do
            {:ok, _post} ->
              send(self(), :load_posts)
              {:noreply,
               socket
               |> assign(:show_compose, false)
               |> assign(:compose_comment, "")
               |> assign(:compose_error, nil)
               |> put_flash(:info, "Posted!")}

            {:error, reason} ->
              {:noreply, assign(socket, :compose_error, "Upload failed: #{inspect(reason)}")}
          end

        _ ->
          {:noreply, assign(socket, :compose_error, "Please select a photo")}
      end
    end
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("delete_post", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    if scope do
      post = Community.get_post(id)
      if post && post.user_id == scope.user.id do
        Community.delete_post(scope, post)
        send(self(), :load_posts)
      end
    end
    {:noreply, socket}
  end

  # ---- Forecast fetching ----

  defp fetch_forecast(lat, lon) do
    now = DateTime.utc_now()

    # Fetch 7 days of hourly data from Open-Meteo
    weather_task = Task.async(fn ->
      Req.get("https://api.open-meteo.com/v1/forecast",
        params: %{
          latitude: lat,
          longitude: lon,
          hourly: "temperature_2m,wind_speed_10m,wind_direction_10m,precipitation_probability,weather_code,wind_gusts_10m",
          forecast_days: 7,
          timezone: "auto"
        }
      )
    end)

    marine_task = Task.async(fn ->
      Req.get("https://marine-api.open-meteo.com/v1/marine",
        params: %{
          latitude: lat,
          longitude: lon,
          hourly: "wave_height,wave_period,wave_direction,sea_surface_temperature,swell_wave_height,swell_wave_period",
          forecast_days: 7,
          timezone: "auto"
        }
      )
    end)

    with {:ok, %{status: 200, body: wb}} <- Task.await(weather_task, 10_000),
         {:ok, %{status: 200, body: mb}} <- Task.await(marine_task, 10_000) do
      hours = build_hourly(wb, mb)
      days = group_by_day(hours)
      {:ok, days, now}
    else
      _ -> {:error, "API unavailable"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp build_hourly(wb, mb) do
    wh = wb["hourly"] || %{}
    mh = mb["hourly"] || %{}

    times = wh["time"] || []

    times
    |> Enum.with_index()
    |> Enum.map(fn {time_str, i} ->
      wave_h = at(mh["wave_height"], i) || 0.0
      wind_kph = at(wh["wind_speed_10m"], i) || 0.0
      wave_dir = at(mh["wave_direction"], i) || 0
      wave_period = at(mh["wave_period"], i) || 0
      swell_h = at(mh["swell_wave_height"], i) || 0.0
      swell_period = at(mh["swell_wave_period"], i) || 0

      roughness = calc_roughness(wave_h, wind_kph, wave_dir)

      %{
        time: parse_time(time_str),
        time_str: time_str,
        temp_c: at(wh["temperature_2m"], i) || 0.0,
        wind_kph: wind_kph,
        wind_dir: at(wh["wind_direction_10m"], i) || 0,
        rain_pct: at(wh["precipitation_probability"], i) || 0,
        wmo_code: at(wh["weather_code"], i) || 0,
        wave_m: wave_h,
        wave_dir: wave_dir,
        wave_period: wave_period,
        swell_m: swell_h,
        swell_period: swell_period,
        sea_temp_c: at(mh["sea_surface_temperature"], i) || 0.0,
        roughness: roughness,
        roughness_status: roughness_status(roughness)
      }
    end)
  end

  defp at(list, i) when is_list(list), do: Enum.at(list, i)
  defp at(_, _), do: nil

  defp parse_time(str) do
    case DateTime.from_iso8601(str <> ":00Z") do
      {:ok, dt, _} -> dt
      _ ->
        case NaiveDateTime.from_iso8601(str <> ":00") do
          {:ok, ndt} -> ndt
          _ -> nil
        end
    end
  end

  defp group_by_day(hours) do
    now = Date.utc_today()

    hours
    |> Enum.group_by(fn h ->
      case h.time do
        %DateTime{} = dt -> DateTime.to_date(dt)
        %NaiveDateTime{} = ndt -> NaiveDateTime.to_date(ndt)
        _ -> now
      end
    end)
    |> Enum.sort_by(fn {date, _} -> date end, Date)
    |> Enum.map(fn {date, day_hours} ->
      label = day_label(date, now)
      %{
        date: date,
        label: label,
        date_str: Calendar.strftime(date, "%d %b"),
        forecasts: day_hours
      }
    end)
  end

  defp day_label(date, today) do
    cond do
      date == Date.add(today, -1) -> "YESTERDAY"
      date == today -> "TODAY"
      date == Date.add(today, 1) -> "TOMORROW"
      true -> date |> Date.day_of_week() |> dow_name() |> String.upcase()
    end
  end

  defp dow_name(1), do: "Monday"
  defp dow_name(2), do: "Tuesday"
  defp dow_name(3), do: "Wednesday"
  defp dow_name(4), do: "Thursday"
  defp dow_name(5), do: "Friday"
  defp dow_name(6), do: "Saturday"
  defp dow_name(7), do: "Sunday"

  defp find_today_index(days) do
    today = Date.utc_today()
    idx = Enum.find_index(days, fn d -> d.date == today end)
    idx || 0
  end

  defp parse_location_param(%{"lat" => lat_s, "lon" => lon_s} = params) do
    with {lat, _} <- Float.parse(lat_s),
         {lon, _} <- Float.parse(lon_s) do
      %{id: "custom", name: params["loc"] || "Shared Location", lat: lat, lon: lon}
    else
      _ -> nil
    end
  end
  defp parse_location_param(_), do: nil

  # ---- Roughness calculation (mirrors Flutter logic) ----

  defp calc_roughness(wave_m, wind_kph, _wave_dir) do
    # Simplified roughness index 0-100
    wave_score = min(wave_m / 2.5, 1.0) * 60
    wind_score = min(wind_kph / 50.0, 1.0) * 40
    round(wave_score + wind_score)
  end

  defp roughness_status(r) when r < 25, do: :calm
  defp roughness_status(r) when r < 50, do: :medium
  defp roughness_status(r) when r < 75, do: :rough
  defp roughness_status(_), do: :unsafe

  # ---- Template helpers (called from HEEx) ----

  def wmo_icon(0), do: "☀️"
  def wmo_icon(c) when c <= 3, do: "⛅"
  def wmo_icon(c) when c <= 48, do: "🌫️"
  def wmo_icon(c) when c <= 67, do: "🌧️"
  def wmo_icon(c) when c <= 77, do: "🌨️"
  def wmo_icon(c) when c <= 82, do: "🌧️"
  def wmo_icon(c) when c <= 86, do: "🌨️"
  def wmo_icon(_), do: "⛈️"

  def swell_arrow(deg) do
    arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
    Enum.at(arrows, round(deg / 45) |> rem(8))
  end

  def roughness_color(:calm), do: "#22C55E"
  def roughness_color(:medium), do: "#3B82F6"
  def roughness_color(:rough), do: "#F97316"
  def roughness_color(:unsafe), do: "#EF4444"

  def roughness_label(:calm), do: "CALM"
  def roughness_label(:medium), do: "MEDIUM"
  def roughness_label(:rough), do: "ROUGH"
  def roughness_label(:unsafe), do: "UNSAFE"

  def format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:00")
  def format_time(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%H:00")
  def format_time(_), do: "--:--"

  def is_current_hour?(%DateTime{} = dt) do
    now = DateTime.utc_now()
    dt.year == now.year && dt.month == now.month && dt.day == now.day && dt.hour == now.hour
  end
  def is_current_hour?(%NaiveDateTime{} = ndt) do
    now = NaiveDateTime.utc_now()
    ndt.year == now.year && ndt.month == now.month && ndt.day == now.day && ndt.hour == now.hour
  end
  def is_current_hour?(_), do: false

  def image_url(image) do
    DipguideBackendWeb.Endpoint.url() <> "/uploads/" <> image.file_key
  end

  def format_distance(nil), do: ""
  def format_distance(d) when d < 1.0, do: "#{round(d * 1000)}m away"
  def format_distance(d), do: "#{Float.round(d, 1)}km away"

  def wave_count(:calm), do: 1
  def wave_count(:medium), do: 2
  def wave_count(_), do: 3

  def time_ago(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
  def time_ago(%NaiveDateTime{} = ndt) do
    time_ago(DateTime.from_naive!(ndt, "Etc/UTC"))
  end
  def time_ago(_), do: ""
end
