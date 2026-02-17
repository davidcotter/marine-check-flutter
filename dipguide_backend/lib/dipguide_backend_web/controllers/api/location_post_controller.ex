defmodule DipguideBackendWeb.Api.LocationPostController do
  use DipguideBackendWeb, :controller

  alias DipguideBackend.Community

  def create(conn, params) do
    upload = Map.get(params, "image") || Map.get(params, "file")

    if match?(%Plug.Upload{}, upload) do
      case Community.create_post(conn.assigns.current_scope, params, upload) do
        {:ok, post} ->
          conn
          |> put_status(:created)
          |> json(%{post: post_json(post, nil)})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: format_error(reason)})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "image is required"})
    end
  end

  def show(conn, %{"id" => id}) do
    case Community.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      post ->
        json(conn, %{post: post_json(post, nil)})
    end
  end

  def public_by_location(conn, %{"lat" => lat, "lon" => lon} = params) do
    radius_km = parse_float(params["radius_km"], 2.0)
    limit = parse_int(params["limit"], 30)

    results =
      Community.list_public_by_location(parse_float(lat, 0.0), parse_float(lon, 0.0),
        radius_km: radius_km,
        limit: limit
      )

    json(conn, %{
      posts: Enum.map(results, fn %{post: p, distance_km: d} -> post_json(p, d) end)
    })
  end

  def nearby_public(conn, %{"lat" => lat, "lon" => lon} = params) do
    radius_km = parse_float(params["radius_km"], 50.0)
    limit = parse_int(params["limit"], 30)

    results =
      Community.list_public_nearby(parse_float(lat, 0.0), parse_float(lon, 0.0),
        radius_km: radius_km,
        limit: limit
      )

    json(conn, %{
      posts: Enum.map(results, fn %{post: p, distance_km: d} -> post_json(p, d) end)
    })
  end

  def my_posts(conn, params) do
    # Manually extract user from Bearer token since this route is in the public pipeline
    # (to avoid the /:id wildcard swallowing "mine")
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, decoded_token} <- Base.url_decode64(token),
         {user, _} <- DipguideBackend.Accounts.get_user_by_session_token(decoded_token) do
      limit = parse_int(params["limit"], 50)
      posts = Community.list_user_posts(user.id, limit: limit)
      json(conn, %{posts: Enum.map(posts, fn p -> post_json(p, nil) end)})
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Community.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      post ->
        case Community.delete_post(conn.assigns.current_scope, post) do
          {:ok, :ok} ->
            json(conn, %{ok: true})

          {:error, :forbidden} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "forbidden"})

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_error(reason)})
        end
    end
  end

  defp post_json(post, distance_km) do
    base = DipguideBackendWeb.Endpoint.url()

    %{
      id: post.id,
      user_id: post.user_id,
      location_name: post.location_name,
      lat: post.lat,
      lon: post.lon,
      comment: post.comment,
      visibility: post.visibility,
      forecast_time: post.forecast_time,
      inserted_at: post.inserted_at,
      distance_km: distance_km,
      images:
        Enum.map(post.images || [], fn img ->
          %{
            id: img.id,
            content_type: img.content_type,
            url: base <> "/uploads/" <> img.file_key
          }
        end)
    }
  end

  defp parse_float(nil, default), do: default

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(val, _default) when is_number(val), do: val * 1.0

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  defp format_error(other), do: other
end
