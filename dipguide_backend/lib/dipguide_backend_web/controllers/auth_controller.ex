defmodule DipguideBackendWeb.AuthController do
  use DipguideBackendWeb, :controller

  plug :store_auth_platform when action in [:request]
  plug Ueberauth

  alias DipguideBackend.Accounts

  defp store_auth_platform(conn, _opts) do
    platform = conn.params["platform"] || "web"
    return_to = sanitize_return_to(conn.params["return_to"])

    conn
    |> put_session(:auth_platform, platform)
    |> put_session(:auth_return_to, return_to)
  end

  def request(conn, _params) do
    # Ueberauth plug handles the redirect to the OAuth provider.
    # This function is only reached if Ueberauth doesn't intercept (shouldn't happen).
    conn
    |> put_flash(:error, "OAuth provider not configured.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    email = auth.info.email
    platform = get_session(conn, :auth_platform) || "web"
    return_to = get_session(conn, :auth_return_to) || "/"

    case Accounts.get_or_register_user_by_email(email) do
      {:ok, user} ->
        api_token = Accounts.generate_user_session_token(user)
        encoded_token = Base.url_encode64(api_token)

        case platform do
          "mobile" ->
            redirect(conn, external: "dipguide://auth?token=#{encoded_token}")

          _ ->
            # Web: redirect to the Flutter web app with the token in the URL
            redirect(conn, to: append_auth_token(return_to, encoded_token))
        end

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Fatal error authenticating.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/")
  end

  defp sanitize_return_to(nil), do: "/"

  defp sanitize_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    else
      "/"
    end
  end

  defp append_auth_token(return_to, encoded_token) do
    uri = URI.parse(return_to)
    params = URI.decode_query(uri.query || "") |> Map.put("auth_token", encoded_token)
    %{uri | query: URI.encode_query(params)} |> URI.to_string()
  end
end
