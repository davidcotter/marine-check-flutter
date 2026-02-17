defmodule DipguideBackendWeb.AppLive.Settings do
  use DipguideBackendWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")}
  end

  @impl true
  def handle_event("logout", _, socket) do
    # Handled via redirect to the existing logout route
    {:noreply, redirect(socket, to: ~p"/users/log-out")}
  end
end
