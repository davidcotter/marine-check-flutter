defmodule DipguideBackend.Repo do
  use Ecto.Repo,
    otp_app: :dipguide_backend,
    adapter: Ecto.Adapters.Postgres
end
