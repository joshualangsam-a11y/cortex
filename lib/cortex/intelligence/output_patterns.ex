defmodule Cortex.Intelligence.OutputPatterns do
  @moduledoc """
  Pattern detection for terminal output.

  Scans a binary string for known patterns (build errors, test results,
  deploy events, etc.) and returns a list of matches with type, severity,
  and a human-readable message.
  """

  @type match :: %{
          type: atom(),
          severity: :info | :warning | :error | :success,
          message: String.t(),
          action_hint: String.t() | nil
        }

  @patterns [
    # Build errors — action-oriented, not passive
    {~r/\*\* \(CompileError\)(.*)/, :build_error, :error, "Compile error",
     "check the file:line in the error"},
    {~r/\*\* \(SyntaxError\)(.*)/, :build_error, :error, "Syntax error",
     "likely a missing end/do/bracket"},
    {~r/BUILD FAILED/i, :build_error, :error, "Build failed", "scroll up for the root cause"},
    {~r/FAILED/, :build_error, :error, "Build failed", "scroll up for the root cause"},
    {~r/(?:^|\n)\s*error:\s*(.+)/i, :build_error, :error, "Build error", nil},
    {~r/(?:^|\n)\s*Error:\s*(.+)/, :build_error, :error, "Build error", nil},

    # Test results
    {~r/(\d+) tests?, (\d+) failures?/, :test_failure, :error, "Test failures detected",
     "run with --trace to isolate"},
    {~r/All (\d+) tests? passed/, :test_success, :success, "All tests passed", nil},
    {~r/0 failures/, :test_success, :success, "Tests passed", nil},

    # Deploy events
    {~r/deploy succeeded/i, :deploy_success, :success, "Deploy succeeded", nil},
    {~r/deploy failed/i, :deploy_failure, :error, "Deploy failed",
     "check build logs for the break"},
    {~r/deployed/i, :deploy_success, :success, "Deployed", nil},

    # Claude CLI completion (box-drawing output)
    {~r/[╭╰│─]{2,}/, :claude_output, :info, "Claude activity detected", nil},

    # Git events
    {~r/Already up to date/, :git_status, :info, "Git: already up to date", nil},
    {~r/Fast-forward/, :git_update, :info, "Git: fast-forward merge", nil},
    {~r/CONFLICT/, :git_conflict, :warning, "Git merge conflict",
     "resolve conflicts then git add"},

    # Server events
    {~r/Running .* at/, :server_started, :info, "Server started", nil},
    {~r/Listening on/, :server_started, :info, "Server listening", nil}
  ]

  @doc """
  Detect known patterns in a binary string.

  Returns a list of `%{type, severity, message}` maps for each match found.
  """
  @spec detect(binary()) :: [match()]
  def detect(output) when is_binary(output) do
    @patterns
    |> Enum.reduce([], fn {regex, type, severity, base_message, action_hint}, acc ->
      case Regex.run(regex, output) do
        nil ->
          acc

        [full_match | captures] ->
          message = build_message(base_message, full_match, captures)
          [%{type: type, severity: severity, message: message, action_hint: action_hint} | acc]
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
