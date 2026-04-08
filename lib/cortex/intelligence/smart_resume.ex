defmodule Cortex.Intelligence.SmartResume do
  @moduledoc """
  Smart Resume: automatic context reconstruction on app launch.

  When Cortex opens with no sessions, SmartResume analyzes:
  1. Pending resume points (what was interrupted)
  2. Last workspace state (what was running)
  3. Energy cycle (is now a good time for that work?)

  Generates a ranked list of resume actions, with the #1 action
  being the strongest Zeigarnik pull — the thing your brain most
  wants to get back to.

  "The system that pulls you back to what matters."
  """

  alias Cortex.Intelligence.{EnergyCycle, ResumePoint}
  alias Cortex.Workspaces

  @doc """
  Generate resume suggestions ranked by urgency and recency.

  Returns a list of %{type, project_name, context, next_action, urgency_score, source}
  """
  def suggestions do
    resume_points = resume_suggestions()
    workspace_suggestions = last_workspace_suggestion()

    all =
      (resume_points ++ workspace_suggestions)
      |> Enum.sort_by(& &1.urgency_score, :desc)
      |> Enum.take(5)

    energy = EnergyCycle.state()

    # If in mud hours, deprioritize high-energy resume points
    if energy.phase == :mud do
      Enum.sort_by(
        all,
        fn s ->
          if s.urgency_score > 80, do: s.urgency_score - 30, else: s.urgency_score
        end,
        :desc
      )
    else
      all
    end
  end

  @doc "Get the single strongest resume action."
  def top_suggestion do
    case suggestions() do
      [] -> nil
      [top | _] -> top
    end
  end

  # Resume points → suggestions

  defp resume_suggestions do
    ResumePoint.pending()
    |> Enum.map(fn rp ->
      urgency = urgency_score(rp)

      %{
        type: :resume_point,
        id: rp.id,
        project_name: rp.project_name,
        context: rp.context,
        next_action: rp.next_action,
        urgency_score: urgency,
        source: "Where you left off",
        age_minutes: age_minutes(rp.inserted_at)
      }
    end)
  end

  defp urgency_score(rp) do
    base =
      case rp.urgency do
        "high" -> 80
        "normal" -> 50
        _ -> 30
      end

    # Recency bonus: more recent = higher urgency
    age = age_minutes(rp.inserted_at)

    recency_bonus =
      cond do
        age < 60 -> 20
        age < 240 -> 10
        age < 1440 -> 5
        true -> 0
      end

    # Context bonus: compile errors and test failures are high-pull
    context_bonus =
      cond do
        rp.context =~ "compile" -> 15
        rp.context =~ "test" -> 10
        rp.context =~ "conflict" -> 15
        rp.context =~ "deploy" -> 10
        true -> 0
      end

    base + recency_bonus + context_bonus
  end

  # Last workspace → suggestion

  defp last_workspace_suggestion do
    case Workspaces.list_workspaces() do
      [] ->
        []

      workspaces ->
        # Find the most recently updated workspace
        latest =
          workspaces
          |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
          |> List.first()

        if latest do
          [
            %{
              type: :workspace,
              id: latest.id,
              project_name: latest.name,
              context: "Workspace: #{latest.name}",
              next_action: "Relaunch #{length(latest.sessions)} sessions",
              urgency_score: 40,
              source: "Last workspace",
              age_minutes: 0
            }
          ]
        else
          []
        end
    end
  rescue
    _ -> []
  end

  defp age_minutes(datetime) do
    DateTime.diff(DateTime.utc_now(), datetime, :second) / 60
  rescue
    _ -> 9999
  end
end
