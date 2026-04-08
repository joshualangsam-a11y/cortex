defmodule Cortex.Intelligence.ResumePoint do
  @moduledoc """
  Zeigarnik-powered resume points.

  When a terminal session exits, analyzes the last output buffer to determine
  what was happening and generates a "resume point" — a short description of
  the unfinished work that pulls the brain back in on next launch.

  Based on the Zeigarnik Effect: incomplete tasks create cognitive tension that
  draws you back. By surfacing what was 90% done, Cortex exploits this to
  maintain momentum across sessions.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cortex.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "resume_points" do
    field(:session_id, :binary_id)
    field(:project_name, :string)
    field(:context, :string)
    field(:next_action, :string)
    field(:status, :string, default: "pending")
    field(:urgency, :string, default: "normal")

    timestamps(type: :utc_datetime)
  end

  def changeset(resume_point, attrs) do
    resume_point
    |> cast(attrs, [:session_id, :project_name, :context, :next_action, :status, :urgency])
    |> validate_required([:context, :next_action])
  end

  @doc "Generate a resume point from terminal output buffer."
  def from_output(session_id, project_name, output) when is_binary(output) do
    # Take last 2KB for analysis
    chunk =
      if byte_size(output) > 2048 do
        binary_part(output, byte_size(output) - 2048, 2048)
      else
        output
      end

    # Strip ANSI escape codes for clean analysis
    clean = strip_ansi(chunk)

    case detect_context(clean) do
      nil ->
        nil

      {context, next_action, urgency} ->
        %__MODULE__{}
        |> changeset(%{
          session_id: session_id,
          project_name: project_name,
          context: context,
          next_action: next_action,
          urgency: urgency,
          status: "pending"
        })
        |> Repo.insert()
    end
  end

  def from_output(_, _, _), do: nil

  @doc "Get all pending resume points, most recent first."
  def pending do
    __MODULE__
    |> where([r], r.status == "pending")
    |> order_by([r], desc: r.inserted_at)
    |> limit(10)
    |> Repo.all()
  end

  @doc "Mark a resume point as resumed (user acted on it)."
  def mark_resumed(id) do
    case Repo.get(__MODULE__, id) do
      nil -> {:error, :not_found}
      rp -> rp |> changeset(%{status: "resumed"}) |> Repo.update()
    end
  end

  @doc "Mark a resume point as dismissed."
  def mark_dismissed(id) do
    case Repo.get(__MODULE__, id) do
      nil -> {:error, :not_found}
      rp -> rp |> changeset(%{status: "dismissed"}) |> Repo.update()
    end
  end

  @doc "Clean up old resume points (older than 3 days)."
  def cleanup do
    cutoff = DateTime.add(DateTime.utc_now(), -3, :day)

    __MODULE__
    |> where([r], r.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  # Pattern detection on terminal output

  defp detect_context(output) do
    cond do
      # Compile errors — you were fixing something
      output =~ ~r/CompileError|SyntaxError|error:.*\.ex:\d+/ ->
        {"Fixing compile errors", "Re-run the build — you were close", "high"}

      # Test failures — you were making tests pass
      match = Regex.run(~r/(\d+) tests?, (\d+) failures?/, output) ->
        [_, total, failures] = match
        {"#{failures}/#{total} tests failing", "Fix the next failing test", "high"}

      # Mix test running — you were in a test cycle
      output =~ ~r/mix test|ExUnit/ ->
        {"Running tests", "Check which tests still need fixing", "normal"}

      # Git operations — you were in the middle of a commit/push cycle
      output =~ ~r/CONFLICT|merge conflict/i ->
        {"Resolving merge conflicts", "Finish resolving conflicts and commit", "high"}

      output =~ ~r/Changes not staged|modified:/ ->
        {"Uncommitted changes", "Stage and commit your work", "normal"}

      # Claude CLI was running — you had an agent working
      output =~ ~r/[╭╰│─]{2,}/ ->
        extract_claude_context(output)

      # Server was running
      output =~ ~r/Running .* at|Listening on/ ->
        {"Dev server was running", "Restart the dev server", "normal"}

      # Deploy in progress
      output =~ ~r/deploy|pushing|Vercel/i ->
        {"Deploy in progress", "Check deploy status", "high"}

      # Generic active session — had recent output
      String.length(String.trim(output)) > 50 ->
        last_line = output |> String.split("\n", trim: true) |> List.last() |> String.trim()

        if String.length(last_line) > 5 do
          truncated = String.slice(last_line, 0, 80)
          {"Session was active", "Last output: #{truncated}", "normal"}
        else
          nil
        end

      true ->
        nil
    end
  end

  defp extract_claude_context(output) do
    # Try to find what Claude was working on from the output
    lines = String.split(output, "\n", trim: true)

    # Look for task descriptions in Claude's output
    task_line =
      lines
      |> Enum.reverse()
      |> Enum.find(fn line ->
        clean = String.trim(line)
        String.length(clean) > 10 and not String.match?(clean, ~r/^[╭╰│─┌└├┤┼]+$/)
      end)

    case task_line do
      nil ->
        {"Claude agent was working", "Check what the agent completed", "normal"}

      line ->
        truncated = line |> String.trim() |> String.slice(0, 80)
        {"Claude agent was working", "Last: #{truncated}", "normal"}
    end
  end

  defp strip_ansi(text) do
    Regex.replace(~r/\x1b\[[0-9;]*[a-zA-Z]/, text, "")
  end
end
