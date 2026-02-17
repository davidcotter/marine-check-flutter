defmodule DipguideBackend.Community do
  @moduledoc """
  Community content: user posts with photos tied to a swim location.
  """

  import Ecto.Query

  alias DipguideBackend.Accounts.Scope
  alias DipguideBackend.Community.{LocationPost, LocationPostImage}
  alias DipguideBackend.Repo

  @allowed_image_exts ~w(.jpg .jpeg .png .webp)
  @allowed_content_types ~w(image/jpeg image/png image/webp)

  def get_post(id) do
    Repo.get(LocationPost, id) |> Repo.preload(:images)
  end

  def get_post!(id) do
    Repo.get!(LocationPost, id) |> Repo.preload(:images)
  end

  @doc "Find a post by a short prefix of its UUID (first 8 chars)."
  def get_post_by_short_id(short) when byte_size(short) >= 6 do
    pattern = short <> "%"

    LocationPost
    |> where([p], fragment("CAST(? AS TEXT) ILIKE ?", p.id, ^pattern))
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      post -> Repo.preload(post, :images)
    end
  end

  def get_post_by_short_id(_), do: nil

  def list_public_by_location(lat, lon, opts \\ []) do
    radius_km = Keyword.get(opts, :radius_km, 2.0)
    limit = Keyword.get(opts, :limit, 30)

    {min_lat, max_lat, min_lon, max_lon} = bounding_box(lat, lon, radius_km)

    LocationPost
    |> where([p], p.visibility == "public")
    |> where(
      [p],
      p.lat >= ^min_lat and p.lat <= ^max_lat and p.lon >= ^min_lon and p.lon <= ^max_lon
    )
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> preload(:images)
    |> Repo.all()
    |> Enum.map(fn post ->
      %{post: post, distance_km: nilify_distance(distance_expr_for_post(post, lat, lon))}
    end)
  end

  def list_public_nearby(lat, lon, opts \\ []) do
    radius_km = Keyword.get(opts, :radius_km, 50.0)
    limit = Keyword.get(opts, :limit, 30)

    {min_lat, max_lat, min_lon, max_lon} = bounding_box(lat, lon, radius_km)

    query =
      from p in LocationPost,
        where: p.visibility == "public",
        where:
          p.lat >= ^min_lat and p.lat <= ^max_lat and p.lon >= ^min_lon and p.lon <= ^max_lon,
        order_by: [
          asc:
            fragment(
              "6371 * 2 * asin(sqrt(power(sin(radians((? - ?) / 2)), 2) + cos(radians(?)) * cos(radians(?)) * power(sin(radians((? - ?) / 2)), 2)))",
              p.lat,
              ^lat,
              ^lat,
              p.lat,
              p.lon,
              ^lon
            ),
          desc: p.inserted_at
        ],
        limit: ^limit,
        select: %{
          post: p,
          distance_km:
            fragment(
              "6371 * 2 * asin(sqrt(power(sin(radians((? - ?) / 2)), 2) + cos(radians(?)) * cos(radians(?)) * power(sin(radians((? - ?) / 2)), 2)))",
              p.lat,
              ^lat,
              ^lat,
              p.lat,
              p.lon,
              ^lon
            )
        }

    results = Repo.all(query)

    post_ids = Enum.map(results, & &1.post.id)

    posts_by_id =
      Repo.all(from p in LocationPost, where: p.id in ^post_ids, preload: [:images])
      |> Map.new(&{&1.id, &1})

    Enum.map(results, fn %{post: p, distance_km: d} ->
      %{post: Map.fetch!(posts_by_id, p.id), distance_km: d}
    end)
  end

  def list_user_posts(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    LocationPost
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> preload(:images)
    |> Repo.all()
  end

  def create_post(%Scope{user: user} = _scope, attrs, %Plug.Upload{} = upload)
      when not is_nil(user) do
    # Posts are always public per product requirements.
    visibility = "public"

    changeset =
      %LocationPost{}
      |> LocationPost.changeset(Map.put(attrs, "visibility", visibility))
      |> Ecto.Changeset.put_change(:user_id, user.id)

    Repo.transaction(fn ->
      post = Repo.insert!(changeset)

      case store_upload(post.id, upload) do
        {:ok, {file_key, content_type}} ->
          _image =
            %LocationPostImage{post_id: post.id}
            |> LocationPostImage.changeset(%{file_key: file_key, content_type: content_type})
            |> Repo.insert!()

          Repo.preload(post, :images)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def delete_post(%Scope{user: user} = _scope, %LocationPost{} = post) when not is_nil(user) do
    if post.user_id != user.id do
      {:error, :forbidden}
    else
      post = Repo.preload(post, :images)

      Repo.transaction(fn ->
        Enum.each(post.images, fn img ->
          delete_upload_file(img.file_key)
        end)

        Repo.delete!(post)
        :ok
      end)
    end
  end

  defp delete_upload_file(file_key) when is_binary(file_key) do
    upload_dir =
      Application.get_env(:dipguide_backend, :upload_dir) || System.get_env("UPLOAD_DIR")

    if upload_dir do
      path = Path.join(upload_dir, file_key)

      try do
        _ = File.rm(path)
      rescue
        _ -> :ok
      end
    end
  end

  defp store_upload(post_id, %Plug.Upload{
         path: src_path,
         filename: filename,
         content_type: content_type
       }) do
    ext =
      filename
      |> Path.extname()
      |> String.downcase()

    ext =
      if ext == ".jpeg" do
        ".jpg"
      else
        ext
      end

    cond do
      ext not in @allowed_image_exts ->
        {:error, "unsupported_image_type"}

      content_type && content_type not in @allowed_content_types ->
        {:error, "unsupported_content_type"}

      true ->
        upload_dir =
          Application.get_env(:dipguide_backend, :upload_dir) ||
            System.get_env("UPLOAD_DIR") ||
            "/var/lib/dipguide_backend/uploads"

        image_id = Ecto.UUID.generate()
        file_key = Path.join(["location_posts", post_id, "#{image_id}#{ext}"])
        dest_path = Path.join(upload_dir, file_key)

        try do
          dest_dir = Path.dirname(dest_path)
          File.mkdir_p!(dest_dir)
          File.cp!(src_path, dest_path)

          final_content_type = content_type || content_type_for_ext(ext)
          {:ok, {file_key, final_content_type}}
        rescue
          _ ->
            {:error, "upload_failed"}
        end
    end
  end

  defp content_type_for_ext(".jpg"), do: "image/jpeg"
  defp content_type_for_ext(".png"), do: "image/png"
  defp content_type_for_ext(".webp"), do: "image/webp"
  defp content_type_for_ext(_), do: "application/octet-stream"

  defp bounding_box(lat, lon, radius_km) do
    # Rough bounding box to keep queries fast
    delta_lat = radius_km / 111.0
    delta_lon = radius_km / ((111.0 * :math.cos(lat * :math.pi() / 180.0)) |> max(0.01))

    {lat - delta_lat, lat + delta_lat, lon - delta_lon, lon + delta_lon}
  end

  defp distance_expr_for_post(%LocationPost{lat: plat, lon: plon}, lat, lon) do
    # compute in Elixir for list_public_by_location; (not used for ordering)
    haversine_km(plat, plon, lat, lon)
  end

  defp nilify_distance(d) when is_number(d), do: d
  defp nilify_distance(_), do: nil

  defp haversine_km(lat1, lon1, lat2, lon2) do
    r = 6371.0
    dlat = :math.pi() * (lat2 - lat1) / 180.0
    dlon = :math.pi() * (lon2 - lon1) / 180.0

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(:math.pi() * lat1 / 180.0) * :math.cos(:math.pi() * lat2 / 180.0) *
          :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    r * c
  end
end
