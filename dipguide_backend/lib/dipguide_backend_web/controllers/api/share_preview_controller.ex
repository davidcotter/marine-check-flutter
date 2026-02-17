defmodule DipguideBackendWeb.Api.SharePreviewController do
  use DipguideBackendWeb, :controller

  alias DipguideBackend.{Community, WeatherShare}
  alias DipguideBackendWeb.ShareController

  @doc """
  Pre-generate a share preview PNG and persist it to disk.
  Returns the static URL so og:image can point to a real file.
  """
  def create(conn, %{"post_id" => post_id}) do
    case Community.get_post(post_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "post not found"})

      post ->
        post_time = post.forecast_time || floor_to_hour(post.inserted_at)

        weather =
          case WeatherShare.get_hour_snapshot(post.lat, post.lon, post_time) do
            {:ok, w} -> w
            _ -> %{}
          end

        # Read and compress photo for WhatsApp (must stay under 300KB total)
        photo_data_uri = ShareController.read_photo_data_uri(post.images)
        svg = ShareController.build_preview_svg(post.location_name, post_time, weather, post.comment, photo_data_uri)

        case generate_and_store(svg, "post_#{post_id}") do
          {:ok, url} -> json(conn, %{preview_url: url})
          :error -> conn |> put_status(:internal_server_error) |> json(%{error: "preview generation failed"})
        end
    end
  end

  def create(conn, %{"lat" => _, "lon" => _, "loc" => _} = params) do
    lat = parse_float(params["lat"])
    lon = parse_float(params["lon"])
    loc = params["loc"] || "Shared Location"
    comment = params["comment"]
    ts = parse_int(params["ts"], DateTime.to_unix(DateTime.utc_now()))
    post_time = DateTime.from_unix!(ts) |> floor_to_hour()

    weather =
      case WeatherShare.get_hour_snapshot(lat, lon, post_time) do
        {:ok, w} -> w
        _ -> %{}
      end

    svg = ShareController.build_preview_svg(loc, post_time, weather, comment)
    key = "forecast_#{:erlang.phash2({lat, lon, loc, ts})}"

    case generate_and_store(svg, key) do
      {:ok, url} -> json(conn, %{preview_url: url})
      :error -> conn |> put_status(:internal_server_error) |> json(%{error: "preview generation failed"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing params"})
  end

  defp generate_and_store(svg, key) do
    upload_dir =
      Application.get_env(:dipguide_backend, :upload_dir) || System.get_env("UPLOAD_DIR")

    previews_dir = Path.join(upload_dir, "previews")
    File.mkdir_p!(previews_dir)

    filename = "#{key}.png"
    dest_path = Path.join(previews_dir, filename)

    case svg_to_png(svg, dest_path) do
      :ok ->
        url = DipguideBackendWeb.Endpoint.url() <> "/uploads/previews/#{filename}"
        {:ok, url}

      :error ->
        :error
    end
  end

  defp svg_to_png(svg, dest_path) do
    tmp_svg = Path.join(System.tmp_dir!(), "preview_#{:erlang.unique_integer([:positive])}.svg")

    try do
      File.write!(tmp_svg, svg)

      case System.cmd("rsvg-convert", ["-w", "1200", "-o", dest_path, tmp_svg],
             stderr_to_stdout: true
           ) do
        {_, 0} -> :ok
        _ -> :error
      end
    rescue
      _ -> :error
    after
      File.rm(tmp_svg)
    end
  end

  defp floor_to_hour(%DateTime{} = dt) do
    ndt = DateTime.to_naive(dt)
    ndt = %{ndt | minute: 0, second: 0, microsecond: {0, 0}}
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp parse_float(v) when is_number(v), do: v * 1.0
  defp parse_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end
  defp parse_float(_), do: 0.0

  defp parse_int(nil, default), do: default
  defp parse_int(v, _default) when is_integer(v), do: v
  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> default
    end
  end
end
