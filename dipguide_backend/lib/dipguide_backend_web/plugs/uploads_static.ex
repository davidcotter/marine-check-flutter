defmodule DipguideBackendWeb.Plugs.UploadsStatic do
  @moduledoc """
  Serves uploaded, user-generated images from the configured upload directory.

  We keep this separate from the compiled `priv/static` assets so uploads are
  writable in production.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    upload_dir =
      Application.get_env(:dipguide_backend, :upload_dir) ||
        System.get_env("UPLOAD_DIR") ||
        "/var/lib/dipguide_backend/uploads"

    # Delegate to Plug.Static, but keep configuration runtime-driven.
    static_opts =
      Plug.Static.init(
        at: "/uploads",
        from: upload_dir,
        gzip: false
      )

    Plug.Static.call(conn, static_opts)
  end
end
