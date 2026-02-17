defmodule DipguideBackendWeb.PageController do
  use DipguideBackendWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def about(conn, _params) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:about)
  end
end
