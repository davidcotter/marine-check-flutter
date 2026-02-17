defmodule DipguideBackendWeb.Router do
  use DipguideBackendWeb, :router

  import DipguideBackendWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DipguideBackendWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_api_user
  end

  pipeline :api_public do
    plug :accepts, ["json"]
  end

  # Phoenix LiveView version of the Flutter app — accessible at /html
  scope "/html", DipguideBackendWeb do
    pipe_through :browser

    live_session :app_live,
      on_mount: [{DipguideBackendWeb.UserAuth, :mount_current_scope}] do
      live "/", AppLive.Home, :index
      live "/login", AppLive.Login, :index
      live "/settings", AppLive.Settings, :index
    end
  end

  scope "/", DipguideBackendWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about
    get "/s/:short_id", ShareController, :short_redirect
    get "/share/posts/:id", ShareController, :post
    get "/share/posts/:id/preview.svg", ShareController, :post_preview
    get "/share/posts/:id/preview.png", ShareController, :post_preview
    get "/share/forecast", ShareController, :forecast
    get "/share/forecast/preview.svg", ShareController, :forecast_preview
    get "/share/forecast/preview.png", ShareController, :forecast_preview
  end

  scope "/auth", DipguideBackendWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end

  # Other scopes may use custom stacks.
  scope "/api", DipguideBackendWeb.Api do
    pipe_through :api_public
    post "/auth/magic-link", AuthController, :create_magic_link

    # Push notification VAPID key (public)
    get "/push/vapid-public-key", PushSubscriptionController, :vapid_public_key
    # Push subscription (no auth required — anonymous subscribers allowed)
    post "/push/subscribe", PushSubscriptionController, :subscribe
    delete "/push/subscribe", PushSubscriptionController, :unsubscribe

    # Public read-only endpoints for sharing + discovery
    get "/location-posts/mine", LocationPostController, :my_posts
    get "/location-posts/:id", LocationPostController, :show
    get "/public/location-posts/by-location", LocationPostController, :public_by_location
    get "/public/location-posts/nearby", LocationPostController, :nearby_public

    # Pre-generate share preview image (static file)
    post "/share/preview", SharePreviewController, :create

    # Met Éireann CORS proxy — fetches XML server-side so the Flutter web app
    # doesn't need a third-party CORS proxy
    get "/proxy/met-eireann", MetEireannProxyController, :forecast

    # Tide CORS proxy — proxies Marine Institute ERDDAP so web doesn't need corsproxy.io
    get "/proxy/tide", TideProxyController, :forecast
  end

  scope "/api", DipguideBackendWeb.Api do
    pipe_through :api
    get "/auth/user", UserSessionController, :show

    # Auth required
    post "/location-posts", LocationPostController, :create
    delete "/location-posts/:id", LocationPostController, :delete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:dipguide_backend, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DipguideBackendWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", DipguideBackendWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{DipguideBackendWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", DipguideBackendWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{DipguideBackendWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
