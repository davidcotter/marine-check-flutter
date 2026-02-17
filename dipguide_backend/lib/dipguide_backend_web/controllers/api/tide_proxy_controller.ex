defmodule DipguideBackendWeb.Api.TideProxyController do
  use DipguideBackendWeb, :controller

  @api_base "https://erddap.marine.ie/erddap/tabledap/imiTidePrediction.json"

  def forecast(conn, %{"q" => query}) do
    url = "#{@api_base}?#{query}"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        json_body = if is_binary(body), do: body, else: Jason.encode!(body)

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(200, json_body)

      {:ok, %{status: status}} ->
        conn |> put_status(status) |> text("Tide upstream error: #{status}")

      {:error, reason} ->
        conn |> put_status(502) |> text("Proxy error: #{inspect(reason)}")
    end
  end

  def forecast(conn, _params) do
    conn |> put_status(400) |> text("Missing q param")
  end
end
