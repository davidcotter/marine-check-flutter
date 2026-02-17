defmodule DipguideBackendWeb.Api.MetEireannProxyController do
  use DipguideBackendWeb, :controller

  @api_base "http://openaccess.pf.api.met.ie/metno-wdb2ts/locationforecast"

  def forecast(conn, %{"lat" => lat, "long" => lon}) do
    url = "#{@api_base}?lat=#{lat}&long=#{lon}"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        conn
        |> put_resp_content_type("application/xml")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(200, body)

      {:ok, %{status: status}} ->
        conn |> put_status(status) |> text("Met Éireann upstream error: #{status}")

      {:error, reason} ->
        conn |> put_status(502) |> text("Proxy error: #{inspect(reason)}")
    end
  end

  def forecast(conn, _params) do
    conn |> put_status(400) |> text("Missing lat/long params")
  end
end
