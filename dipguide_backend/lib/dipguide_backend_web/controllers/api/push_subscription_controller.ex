defmodule DipguideBackendWeb.Api.PushSubscriptionController do
  use DipguideBackendWeb, :controller

  alias DipguideBackend.Notifications

  @doc "Subscribe: POST /api/push/subscribe"
  def subscribe(conn, %{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}}) do
    user_id = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:id)])

    attrs = %{endpoint: endpoint, p256dh: p256dh, auth: auth, user_id: user_id}

    case Notifications.upsert_subscription(attrs) do
      {:ok, _sub} ->
        json(conn, %{ok: true})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  def subscribe(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "endpoint and keys (p256dh, auth) are required"})
  end

  @doc "Unsubscribe: DELETE /api/push/subscribe"
  def unsubscribe(conn, %{"endpoint" => endpoint}) do
    Notifications.delete_subscription(endpoint)
    json(conn, %{ok: true})
  end

  def unsubscribe(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "endpoint is required"})
  end

  @doc "Return the VAPID public key: GET /api/push/vapid-public-key"
  def vapid_public_key(conn, _params) do
    key = Application.get_env(:dipguide_backend, :vapid_public_key, "")
    json(conn, %{vapid_public_key: key})
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
