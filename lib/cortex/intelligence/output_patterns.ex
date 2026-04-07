defmodule Cortex.Intelligence.OutputPatterns do
  @moduledoc """
  Pattern detection for terminal output.

  Scans a binary string for known patterns (build errors, test results,
  deploy events, etc.) and returns a list of matches with type, severity,
  and a human-readable message.
  """

  @type match :: %{type: atom(), severity: :info | :warning | :error | :success, message: String.t()}

  @patterns [
    # Build errors
    {~r/\*\* \(CompileError\)(.*)/, :build_error, :error, "Compile error"},
    {~r/\*\* \(SyntaxError\)(.*)/, :build_error, :error, "Syntax error"},
    {~r/BUILD FAILED/i, :build_error, :error, "Build failed"},
    {~r/FAILED/, :build_error, :error, "Build failed"},
    {~r/(?:^|\n)\s*error:\s*(.+)/i, :build_error, :error, "Build error"},
    {~r/(?:^|\n)\s*Error:\s*(.+)/, :build_error, :error, "Build error"},

    # Test results
    {~r/(\d+) tests?, (\d+) failures?/, :test_failure, :error, "Test failures detected"},
    {~r/All (\d+) tests? passed/, :test_success, :success, "All tests passed"},
    {~r/0 failures/, :test_success, :success, "Tests passed"},

    # Deploy events
    {~r/deploy succeeded/i, :deploy_success, :success, "Deploy succeeded"},
    {~r/deploy failed/i, :deploy_failure, :error, "Deploy failed"},
    {~r/deployed/i, :deploy_success, :success, "Deployed"},

    # Claude CLI completion (box-drawing output)
    {~r/[╭╰│─]{2,}/, :claude_output, :info, "Claude activity detected"},

    # Git events
    {~r/Already up to date/, :git_status, :info, "Git: already up to date"},
    {~r/Fast-forward/, :git_update, :info, "Git: fast-forward merge"},
    {~r/CONFLICT/, :git_conflict, :warning, "Git merge conflict"},

    # Server events
    {~r/Running .* at/, :server_started, :info, "Server started"},
    {~r/Listening on/, :server_started, :info, "Server listening"}
  ]

  @doc """
  Detect known patterns in a binary string.

  Returns a list of `%{type, severity, message}` maps for each match found.
  """
  @spec detect(binary()) :: [match()]
  def detect(output) when is_binary(output) do
    @patterns
    |> Enum.reduce([], fn {regex, type, severity, base_message}, acc ->
      case Regex.run(regex, output) do
        nil ->
          acc

        [full_match | captures] ->
          message = build_message(base_message, full_match, captures)
          [%{type: type, severity: severity, message: message} | acc]
      end
    end)
    |> Enum.reverse()
  end

  def detect(_), do: []

  defp build_message(base_message, _full_match, [detail | _]) when byte_size(detail) > 0 do
    detail = detail |> String.trim() |> String.slice(0, 120)
    "#{base_message}: #{detail}"
  end

  defp build_message(base_message, _full_match, _captures), do: base_message
end
