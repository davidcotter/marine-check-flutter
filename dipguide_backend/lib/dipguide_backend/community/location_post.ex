defmodule DipguideBackend.Community.LocationPost do
  use Ecto.Schema

  import Ecto.Changeset

  alias DipguideBackend.Accounts.User
  alias DipguideBackend.Community.LocationPostImage

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "location_posts" do
    field :location_name, :string
    field :lat, :float
    field :lon, :float
    field :comment, :string
    field :visibility, :string, default: "unlisted"
    field :forecast_time, :utc_datetime

    belongs_to :user, User
    has_many :images, LocationPostImage, foreign_key: :post_id

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:location_name, :lat, :lon, :comment, :visibility, :forecast_time])
    |> validate_required([:location_name, :lat, :lon, :visibility])
    |> validate_inclusion(:visibility, ["unlisted", "public"])
    |> validate_number(:lat, greater_than: -90, less_than: 90)
    |> validate_number(:lon, greater_than: -180, less_than: 180)
    |> validate_length(:comment, max: 500)
  end
end
