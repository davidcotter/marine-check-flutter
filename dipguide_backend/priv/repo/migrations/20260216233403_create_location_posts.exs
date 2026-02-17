defmodule DipguideBackend.Repo.Migrations.CreateLocationPosts do
  use Ecto.Migration

  def change do
    create table(:location_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :location_name, :string, null: false
      add :lat, :float, null: false
      add :lon, :float, null: false

      add :comment, :string

      # "unlisted" = visible to anyone with the link, not discoverable by nearby search
      # "public"   = discoverable by nearby search
      add :visibility, :string, null: false, default: "unlisted"

      # Optional: the forecast hour this post was associated with (UTC)
      add :forecast_time, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:location_posts, [:user_id])
    create index(:location_posts, [:visibility])
    create index(:location_posts, [:lat, :lon])

    create table(:location_post_images, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :post_id, references(:location_posts, type: :binary_id, on_delete: :delete_all),
        null: false

      # Relative path under /uploads, eg: "location_posts/<post_id>/<image_id>.jpg"
      add :file_key, :string, null: false
      add :content_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:location_post_images, [:post_id])
    create unique_index(:location_post_images, [:file_key])
  end
end
