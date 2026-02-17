defmodule DipguideBackendWeb.UserLive.Login do
  use DipguideBackendWeb, :live_view

  alias DipguideBackend.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                Don't have an account? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >Sign up</.link> for an account now.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <input type="hidden" name="platform" value={@platform} />
          <input type="hidden" name="return_to" value={@return_to} />
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">or</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name="platform" value={@platform} />
          <input type="hidden" name="return_to" value={@return_to} />
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Log in and stay logged in <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Log in only this time
          </.button>
        </.form>

        <div class="divider">or continue with</div>

        <div class="grid grid-cols-1 gap-2">
          <.link
            href={~p"/auth/google?platform=web&return_to=#{@return_to}"}
            class="btn btn-outline w-full"
          >
            Google
          </.link>
          <.link href={~p"/auth/github"} class="btn btn-outline w-full">
            GitHub
          </.link>
          <.link href={~p"/auth/apple"} class="btn btn-outline w-full">
            Apple
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")
    platform = get_in(params, ["platform"])
    platform = if platform in [nil, ""], do: "web", else: platform
    return_to = sanitize_return_to(get_in(params, ["return_to"]))

    {:ok,
     assign(socket, form: form, trigger_submit: false, platform: platform, return_to: return_to)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case Accounts.get_or_register_user_by_email(email) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(
          user,
          &url(
            ~p"/users/log-in/#{&1}?platform=#{socket.assigns.platform}&return_to=#{socket.assigns.return_to}"
          )
        )

      {:error, _changeset} ->
        # Potentially log error
        :ok
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp sanitize_return_to(nil), do: "/"

  defp sanitize_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    else
      "/"
    end
  end

  defp local_mail_adapter? do
    Application.get_env(:dipguide_backend, DipguideBackend.Mailer)[:adapter] ==
      Swoosh.Adapters.Local
  end
end
