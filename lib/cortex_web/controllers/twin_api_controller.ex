defmodule CortexWeb.TwinApiController do
  @moduledoc """
  API endpoints for Digital Twin ↔ Cortex communication.

  The twin pushes insights, reads state, and syncs theory.
  No auth required — local-only API (localhost:3012).
  """

  use CortexWeb, :controller

  alias Cortex.Intelligence.{MomentumEngine, ThermalThrottle}

  def state(conn, _params) do
    momentum = safe_call(fn -> MomentumEngine.state() end, %{})
    thermal = safe_call(fn -> ThermalThrottle.state() end, %{})

    json(conn, %{
      momentum: momentum,
      thermal: thermal,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  def insight(conn, %{"type" => type} = params) do
    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      "intelligence:twin",
      {:twin_insight, %{type: type, data: params}}
    )

    json(conn, %{status: "received", type: type})
  end

  def insight(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "missing type field"})
  end

  defp safe_call(fun, default) do
    try do
      fun.()
    rescue
      _ -> default
    catch
      :exit, _ -> default
    end
  end
end
