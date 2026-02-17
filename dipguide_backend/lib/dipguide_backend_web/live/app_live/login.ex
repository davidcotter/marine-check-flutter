defmodule DipguideBackendWeb.AppLive.Login do
  use DipguideBackendWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign In")
     |> assign(:email, "")
     |> assign(:loading, false)
     |> assign(:sent, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("update_email", %{"value" => val}, socket) do
    {:noreply, assign(socket, :email, val)}
  end

  def handle_event("request_magic_link", _params, socket) do
    email = String.trim(socket.assigns.email)

    if email == "" do
      {:noreply, assign(socket, :error, "Please enter your email")}
    else
      socket = assign(socket, :loading, true)

      case send_magic_link(email) do
        :ok ->
          {:noreply,
           socket
           |> assign(:loading, false)
           |> assign(:sent, true)
           |> assign(:error, nil)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:loading, false)
           |> assign(:error, reason)}
      end
    end
  end

  defp send_magic_link(email) do
    case DipguideBackend.Accounts.get_or_register_user_by_email(email) do
      {:ok, user} ->
        DipguideBackend.Accounts.deliver_login_instructions(
          user,
          &url(~p"/users/log-in/#{&1}?return_to=/html")
        )
        :ok

      {:error, _} ->
        {:error, "Invalid email address"}
    end
  rescue
    _ -> {:error, "Could not send magic link. Please try again."}
  end
end
