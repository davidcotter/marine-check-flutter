defmodule DipguideBackend.WeatherShare do
  @moduledoc """
  Fetches a small "share card" weather snapshot for a given hour using Open-Meteo.

  This is used for social share previews and the public share page.
  """

  @forecast_url "https://api.open-meteo.com/v1/forecast"
  @marine_url "https://marine-api.open-meteo.com/v1/marine"

  def get_hour_snapshot(lat, lon, %DateTime{} = dt_utc) do
    hour_key = Calendar.strftime(dt_utc, "%Y-%m-%dT%H:00")

    weather_task =
      Task.async(fn ->
        Req.get(@forecast_url,
          params: %{
            latitude: lat,
            longitude: lon,
            hourly: "temperature_2m,wind_speed_10m,wind_direction_10m,precipitation_probability",
            timezone: "UTC"
          }
        )
      end)

    marine_task =
      Task.async(fn ->
        Req.get(@marine_url,
          params: %{
            latitude: lat,
            longitude: lon,
            hourly: "wave_height,wave_period,wave_direction",
            timezone: "UTC"
          }
        )
      end)

    weather =
      extract_hour(await_req(weather_task), hour_key, "hourly", %{
        "temperature_2m" => :temperature_c,
        "wind_speed_10m" => :wind_kph,
        "wind_direction_10m" => :wind_dir,
        "precipitation_probability" => :rain_pct
      })

    marine =
      extract_hour(await_req(marine_task), hour_key, "hourly", %{
        "wave_height" => :wave_m,
        "wave_period" => :wave_s,
        "wave_direction" => :wave_dir
      })

    {:ok, Map.merge(weather, marine)}
  rescue
    _ -> {:error, :unavailable}
  end

  defp await_req(task) do
    case Task.await(task, 8_000) do
      {:ok, resp} -> resp
      resp -> resp
    end
  end

  defp extract_hour(%Req.Response{status: 200, body: body}, hour_key, parent, fields) do
    hourly = get_in(body, [parent]) || %{}
    times = Map.get(hourly, "time") || []
    idx = Enum.find_index(times, &(&1 == hour_key))

    if is_integer(idx) do
      Enum.reduce(fields, %{}, fn {json_key, out_key}, acc ->
        values = Map.get(hourly, json_key) || []
        Map.put(acc, out_key, Enum.at(values, idx))
      end)
    else
      %{}
    end
  end

  defp extract_hour(_resp, _hour_key, _parent, _fields), do: %{}
end
