defmodule DipguideBackend.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DipguideBackendWeb.Telemetry,
      DipguideBackend.Repo,
      {DNSCluster, query: Application.get_env(:dipguide_backend, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DipguideBackend.PubSub},
      # Start a worker by calling: DipguideBackend.Worker.start_link(arg)
      # {DipguideBackend.Worker, arg},
      # Start to serve requests, typically the last entry
      DipguideBackendWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DipguideBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DipguideBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
