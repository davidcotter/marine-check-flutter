defmodule DipguideBackend.Community.LocationPostImage do
  use Ecto.Schema

  import Ecto.Changeset

  alias DipguideBackend.Community.LocationPost

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "location_post_images" do
    field :file_key, :string
    field :content_type, :string

    belongs_to :post, LocationPost, foreign_key: :post_id

    timestamps(type: :utc_datetime)
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [:file_key, :content_type])
    |> validate_required([:file_key, :content_type])
    |> validate_length(:file_key, max: 500)
    |> validate_length(:content_type, max: 200)
  end
end
