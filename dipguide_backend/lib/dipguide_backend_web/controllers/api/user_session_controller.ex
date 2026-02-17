defmodule DipguideBackendWeb.Api.UserSessionController do
  use DipguideBackendWeb, :controller

  def show(conn, _params) do
    user = conn.assigns.current_scope.user

    conn
    |> put_status(:ok)
    |> json(%{
      email: user.email,
      id: user.id
    })
  end
end
