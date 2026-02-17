defmodule DipguideBackend.Notifications.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    belongs_to :user, DipguideBackend.Accounts.User

    timestamps()
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:endpoint, :p256dh, :auth, :user_id])
    |> validate_required([:endpoint, :p256dh, :auth])
    |> unique_constraint(:endpoint)
  end
end
