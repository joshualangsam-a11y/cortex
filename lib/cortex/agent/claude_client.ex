defmodule Cortex.Agent.ClaudeClient do
  @moduledoc false

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  @doc """
  Streams a Claude API response, sending parsed SSE events to `caller` as messages.

  Events sent to caller:
  - `{:claude_event, map}` — each parsed SSE event
  - `{:claude_done, :ok}` — stream completed successfully
  - `{:claude_error, reason}` — stream failed
  """
  def stream_message(caller, messages, opts \\ []) do
    model = opts[:model] || "claude-sonnet-4-6"
    tools = opts[:tools] || []
    system = opts[:system]
    max_tokens = opts[:max_tokens] || 8192

    body =
      %{model: model, messages: messages, max_tokens: max_tokens, stream: true}
      |> maybe_put(:system, system)
      |> maybe_put(:tools, if(tools != [], do: tools))

    Process.put(:sse_buffer, "")

    result =
      Req.post(@api_url,
        json: body,
        headers: headers(),
        into: fn {:data, chunk}, {req, resp} ->
          buffer = Process.get(:sse_buffer, "")
          {events, new_buffer} = parse_sse_chunk(chunk, buffer)
          Process.put(:sse_buffer, new_buffer)
          Enum.each(events, &send(caller, {:claude_event, &1}))
          {:cont, {req, resp}}
        end,
        receive_timeout: 300_000,
        connect_options: [timeout: 30_000]
      )

    Process.delete(:sse_buffer)

    case result do
      {:ok, _} -> send(caller, {:claude_done, :ok})
      {:error, reason} -> send(caller, {:claude_error, reason})
    end
  end

  @doc """
  Non-streaming message send. Returns the full response.
  """
  def send_message(messages, opts \\ []) do
    model = opts[:model] || "claude-sonnet-4-6"
    tools = opts[:tools] || []
    system = opts[:system]
    max_tokens = opts[:max_tokens] || 8192

    body =
      %{model: model, messages: messages, max_tokens: max_tokens}
      |> maybe_put(:system, system)
      |> maybe_put(:tools, if(tools != [], do: tools))

    case Req.post(@api_url, json: body, headers: headers(), receive_timeout: 300_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # SSE Parsing

  def parse_sse_chunk(chunk, buffer) do
    full = buffer <> chunk
    parts = String.split(full, "\n\n")
    {complete, [remaining]} = Enum.split(parts, -1)

    events =
      complete
      |> Enum.map(&parse_sse_event/1)
      |> Enum.reject(&is_nil/1)

    {events, remaining}
  end

  defp parse_sse_event(raw) do
    raw
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      cond do
        String.starts_with?(line, "event: ") ->
          Map.put(acc, :event, String.trim_leading(line, "event: "))

        String.starts_with?(line, "data: ") ->
          case Jason.decode(String.trim_leading(line, "data: ")) do
            {:ok, data} -> Map.put(acc, :data, data)
            _ -> acc
          end

        true ->
          acc
      end
    end)
    |> then(fn parsed ->
      if Map.has_key?(parsed, :data), do: parsed, else: nil
    end)
  end

  defp headers do
    [
      {"x-api-key", api_key()},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]
  end

  defp api_key do
    Application.get_env(:cortex, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY") ||
      raise "ANTHROPIC_API_KEY not configured. Set it in config or ANTHROPIC_API_KEY env var."
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
