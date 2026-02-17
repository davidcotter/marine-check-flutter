defmodule DipguideBackend.Notifications do
  @moduledoc "Push notification subscription management and delivery."

  import Ecto.Query
  alias DipguideBackend.Notifications.PushSubscription
  alias DipguideBackend.Repo

  @doc "Upsert a push subscription (insert or update by endpoint)."
  def upsert_subscription(attrs) do
    %PushSubscription{}
    |> PushSubscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:p256dh, :auth, :user_id, :updated_at]},
      conflict_target: :endpoint
    )
  end

  @doc "Delete a subscription by endpoint."
  def delete_subscription(endpoint) do
    Repo.delete_all(from s in PushSubscription, where: s.endpoint == ^endpoint)
    :ok
  end

  @doc "List all subscriptions (optionally filtered by user_id)."
  def list_subscriptions(user_id \\ nil) do
    query = from s in PushSubscription
    query = if user_id, do: where(query, [s], s.user_id == ^user_id), else: query
    Repo.all(query)
  end

  @doc """
  Send a push notification to a single subscription.
  Returns :ok or {:error, reason}.
  """
  def send_push(%PushSubscription{} = sub, payload) when is_map(payload) do
    subscription = %{
      keys: %{p256dh: sub.p256dh, auth: sub.auth},
      endpoint: sub.endpoint
    }

    message = Jason.encode!(payload)

    case WebPushEncryption.send_web_push(message, subscription, vapid_details()) do
      {:ok, %{status_code: code}} when code in 200..299 -> :ok
      {:ok, %{status_code: 410}} ->
        # Subscription expired — clean it up
        delete_subscription(sub.endpoint)
        {:error, :gone}
      {:ok, %{status_code: code}} -> {:error, {:http, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Broadcast a push notification to all subscriptions."
  def broadcast(payload) when is_map(payload) do
    list_subscriptions()
    |> Enum.each(fn sub ->
      send_push(sub, payload)
    end)
  end

  defp vapid_details do
    subject = Application.get_env(:dipguide_backend, :vapid_subject, "mailto:admin@dipguide.com")
    public_key = Application.get_env(:dipguide_backend, :vapid_public_key, "")
    private_key = Application.get_env(:dipguide_backend, :vapid_private_key, "")
    {subject, public_key, private_key}
  end
end
