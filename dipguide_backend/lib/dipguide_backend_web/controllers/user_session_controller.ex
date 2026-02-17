defmodule DipguideBackendWeb.UserSessionController do
  use DipguideBackendWeb, :controller

  alias DipguideBackend.Accounts
  alias DipguideBackendWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params} = params, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)
        platform = params["platform"]

        case platform do
          "mobile" ->
            # Mobile app: redirect to deep link
            api_token = Accounts.generate_user_session_token(user)
            redirect(conn, external: "dipguide://auth?token=#{Base.url_encode64(api_token)}")

          "web" ->
            # Flutter web app: redirect with token in URL
            api_token = Accounts.generate_user_session_token(user)
            return_to = sanitize_return_to(params["return_to"])
            redirect(conn, to: append_auth_token(return_to, Base.url_encode64(api_token)))

          _ ->
            # Default Phoenix web session login
            conn
            |> put_flash(:info, info)
            |> UserAuth.log_in_user(user, user_params)
        end

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
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
