defmodule DipguideBackendWeb.Api.AuthController do
  use DipguideBackendWeb, :controller

  alias DipguideBackend.Accounts

  def create_magic_link(conn, %{"email" => email} = params) do
    # Default to "web" for API requests (Flutter web app)
    # Mobile apps can pass platform=mobile explicitly
    platform = params["platform"] || "web"
    return_to = sanitize_return_to(params["return_to"])

    case Accounts.get_or_register_user_by_email(email) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(
          user,
          &url(~p"/users/log-in/#{&1}?platform=#{platform}&return_to=#{return_to}")
        )

        conn
        |> put_status(:ok)
        |> json(%{message: "Magic link sent successfully"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid email address"})
    end
  end

  defp sanitize_return_to(nil), do: "/"

  defp sanitize_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    else
      "/"
    end
  end
end
