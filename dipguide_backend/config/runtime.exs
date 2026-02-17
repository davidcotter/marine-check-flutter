import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/dipguide_backend start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :dipguide_backend, DipguideBackendWeb.Endpoint, server: true
end

config :dipguide_backend, DipguideBackendWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4040"))]

default_upload_dir =
  if config_env() == :prod do
    # Must NOT live under /opt/dipguide_backend because deploy uses rsync --delete there.
    "/var/lib/dipguide_backend/uploads"
  else
    Path.expand("../uploads", __DIR__)
  end

config :dipguide_backend, :upload_dir, System.get_env("UPLOAD_DIR") || default_upload_dir

if config_env() == :prod do
  # Google OAuth credentials (required for Google Sign-In)
  # Not raising on missing values so migrations and admin commands still work
  google_client_id = System.get_env("GOOGLE_CLIENT_ID")
  google_client_secret = System.get_env("GOOGLE_CLIENT_SECRET")

  if google_client_id && google_client_secret do
    config :ueberauth, Ueberauth.Strategy.Google.OAuth,
      client_id: google_client_id,
      client_secret: google_client_secret
  end

  # VAPID keys for Web Push Notifications
  vapid_public_key = System.get_env("VAPID_PUBLIC_KEY")
  vapid_private_key = System.get_env("VAPID_PRIVATE_KEY")
  vapid_subject = System.get_env("VAPID_SUBJECT") || "mailto:admin@dipguide.com"

  if vapid_public_key && vapid_private_key do
    config :dipguide_backend,
      vapid_subject: vapid_subject,
      vapid_public_key: vapid_public_key,
      vapid_private_key: vapid_private_key
  end

  # SMTP Mailer configuration (Brevo/Sendinblue)
  smtp_server = System.get_env("SMTP_SERVER")
  smtp_username = System.get_env("SMTP_USERNAME")
  smtp_password = System.get_env("SMTP_PASSWORD")

  if smtp_server && smtp_username && smtp_password do
    config :dipguide_backend, DipguideBackend.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_server,
      port: 587,
      username: smtp_username,
      password: smtp_password,
      tls: :if_available,
      auth: :always,
      retries: 2
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :dipguide_backend, DipguideBackend.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :dipguide_backend, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :dipguide_backend, DipguideBackendWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :dipguide_backend, DipguideBackendWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :dipguide_backend, DipguideBackendWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :dipguide_backend, DipguideBackend.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
