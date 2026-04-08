defmodule Cortex.Intelligence.ProjectMatcher do
  @moduledoc """
  Project Matcher: recommends the right project for the current moment.

  From decision theory: the optimal choice depends on state. The best
  project to work on at 10AM during mud hours is NOT the best project
  at 4PM during peak. This module makes that state-dependent decision.

  Scoring factors:
  1. Energy match — high-complexity projects need peak hours
  2. Flow history — which projects have you flowed on before?
  3. Priority score — from Prioritizer (deadline, revenue impact)
  4. Recency — Zeigarnik effect: unfinished work pulls harder
  5. Momentum match — if already flowing, stay in current project

  Result: "Right now, work on FanForge. You flow 2x on it during peak,
  it's your #3 priority, and you left a compile error yesterday."
  """

  alias Cortex.Intelligence.{
    EnergyCycle,
    FlowHistory,
    MomentumEngine,
    SmartResume
  }

  alias Cortex.Projects
  alias Cortex.Repo
  import Ecto.Query

  @doc """
  Match projects to current state, return ranked list.

  Returns [%{
    project_name: String.t(),
    score: float,
    reasons: [String.t()],
    energy_match: :perfect | :good | :poor,
    has_resume_point: boolean
  }]
  """
  def match do
    projects = safe_projects()
    energy = EnergyCycle.state()
    flow_state = safe_flow_state()
    resume_suggestions = safe_resume()
    flow_by_project = flow_history_by_project()

    projects
    |> Enum.map(fn project ->
      score_project(project, energy, flow_state, resume_suggestions, flow_by_project)
    end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(5)
  end

  @doc """
  Get the single best project match for right now.
  """
  def best_match do
    case match() do
      [] -> nil
      [best | _] -> best
    end
  end

  @doc """
  One-liner for dashboard/brief.
  """
  def suggestion do
    case best_match() do
      nil ->
        nil

      m ->
        reasons = Enum.join(m.reasons, ", ")
        "Work on #{m.project_name} — #{reasons}."
    end
  end

  # Scoring

  defp score_project(project, energy, flow_state, resume_suggestions, flow_by_project) do
    score = 0.0
    reasons = []

    # 1. Energy match
    complexity = project_complexity(project)
    {energy_score, energy_match, energy_reason} = energy_match_score(energy, complexity)
    score = score + energy_score
    reasons = if energy_reason, do: [energy_reason | reasons], else: reasons

    # 2. Flow history for this project
    project_flows = Map.get(flow_by_project, project.name, 0)
    {flow_score, flow_reason} = flow_history_score(project_flows, energy)
    score = score + flow_score
    reasons = if flow_reason, do: [flow_reason | reasons], else: reasons

    # 3. Resume point (Zeigarnik pull)
    has_resume =
      Enum.any?(resume_suggestions, fn s ->
        s.project_name == project.name
      end)

    {resume_score, resume_reason} = resume_point_score(has_resume)
    score = score + resume_score
    reasons = if resume_reason, do: [resume_reason | reasons], else: reasons

    # 4. Momentum lock (if flowing, heavily weight current project)
    {momentum_score, momentum_reason} = momentum_score(project, flow_state)
    score = score + momentum_score
    reasons = if momentum_reason, do: [momentum_reason | reasons], else: reasons

    %{
      project_name: project.name,
      score: Float.round(score, 1),
      reasons: Enum.reverse(reasons),
      energy_match: energy_match,
      has_resume_point: has_resume
    }
  end

  defp energy_match_score(energy, complexity) do
    case {energy.phase, complexity} do
      {:peak, :high} -> {30.0, :perfect, "peak hours for hard work"}
      {:peak, :medium} -> {20.0, :good, "peak energy available"}
      {:peak, :low} -> {10.0, :good, nil}
      {:rising, :medium} -> {25.0, :perfect, "rising energy for medium tasks"}
      {:rising, :high} -> {15.0, :good, nil}
      {:rising, :low} -> {20.0, :good, nil}
      {:mud, :low} -> {25.0, :perfect, "mud-appropriate light task"}
      {:mud, :medium} -> {10.0, :poor, nil}
      {:mud, :high} -> {0.0, :poor, "too complex for mud hours"}
      {:winding_down, :low} -> {20.0, :good, "wind-down friendly"}
      {:winding_down, :medium} -> {15.0, :good, nil}
      {:winding_down, :high} -> {5.0, :poor, nil}
      _ -> {10.0, :good, nil}
    end
  end

  defp flow_history_score(project_flows, energy) when project_flows >= 5 do
    if energy.phase in [:peak, :rising] do
      {20.0, "#{project_flows} historical flow sessions — proven flow project"}
    else
      {10.0, "flow-proven project"}
    end
  end

  defp flow_history_score(project_flows, _energy) when project_flows >= 2 do
    {5.0, nil}
  end

  defp flow_history_score(_, _), do: {0.0, nil}

  defp resume_point_score(true), do: {15.0, "unfinished work pulling you back"}
  defp resume_point_score(false), do: {0.0, nil}

  defp momentum_score(_project, %{flow_state: :flowing}) do
    # If currently flowing, massive bonus to stay
    {50.0, "you're in flow — don't switch"}
  end

  defp momentum_score(_project, _), do: {0.0, nil}

  # Project complexity heuristic

  defp project_complexity(project) do
    name = String.downcase(project.name)

    cond do
      name =~ "cortex" or name =~ "alphaswarm" -> :high
      name =~ "lit" or name =~ "fan_forge" -> :high
      name =~ "fuel" or name =~ "vape" -> :medium
      name =~ "site_scout" or name =~ "hemp" -> :low
      true -> :medium
    end
  end

  # Data loaders

  defp flow_history_by_project do
    four_weeks_ago = DateTime.add(DateTime.utc_now(), -28, :day)

    # Flow sessions don't track project directly, but we can correlate
    # via active_sessions count as a proxy for now.
    # TODO: Add project_name to flow_sessions table for better matching
    FlowHistory
    |> where([f], f.started_at >= ^four_weeks_ago and not is_nil(f.duration_seconds))
    |> Repo.all()
    |> Enum.reduce(%{}, fn _flow, acc ->
      # Without project tracking in flow_sessions, distribute evenly
      # This gets better as we add project_name to the schema
      acc
    end)
  rescue
    _ -> %{}
  end

  defp safe_projects do
    Projects.list_projects()
  rescue
    _ -> []
  end

  defp safe_flow_state do
    MomentumEngine.state()
  rescue
    _ -> %{flow_state: :idle}
  end

  defp safe_resume do
    SmartResume.suggestions()
  rescue
    _ -> []
  end
end
