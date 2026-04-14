defmodule Cortex.Agent.ModelRouter do
  @moduledoc false

  @opus "claude-opus-4-6"
  @sonnet "claude-sonnet-4-6"
  @haiku "claude-haiku-4-5-20251001"

  def opus, do: @opus
  def sonnet, do: @sonnet
  def haiku, do: @haiku

  def all_models, do: [@haiku, @sonnet, @opus]

  @doc "Auto-select model based on message content and context."
  def route(message, opts \\ []) do
    cond do
      opts[:force] -> opts[:force]
      opts[:tool_continuation] -> @sonnet
      architectural?(message) -> @opus
      simple_query?(message) -> @haiku
      true -> @sonnet
    end
  end

  defp architectural?(msg) do
    lower = String.downcase(msg)

    Enum.any?(
      ~w(architect design refactor restructure migration system plan rewrite overhaul),
      &String.contains?(lower, &1)
    )
  end

  defp simple_query?(msg) do
    short = String.length(msg) < 80
    lower = String.downcase(msg)

    question =
      Enum.any?(
        ["what is", "where is", "find ", "show me", "list ", "how many", "which file"],
        &String.contains?(lower, &1)
      )

    short and (question or String.ends_with?(String.trim(msg), "?"))
  end

  def label(@opus), do: "opus"
  def label(@sonnet), do: "sonnet"
  def label(@haiku), do: "haiku"
  def label(m), do: m |> String.split("-") |> Enum.at(-2, "unknown")

  def color(@opus), do: "#c084fc"
  def color(@sonnet), do: "#ffd04a"
  def color(@haiku), do: "#5ea85e"
  def color(_), do: "#5a5a5a"

  # Cost per 1M tokens {input, output}
  def pricing(@opus), do: {15.0, 75.0}
  def pricing(@sonnet), do: {3.0, 15.0}
  def pricing(@haiku), do: {0.25, 1.25}
  def pricing(_), do: {3.0, 15.0}

  def estimate_cost(model, input_tokens, output_tokens) do
    {input_rate, output_rate} = pricing(model)
    input_tokens / 1_000_000 * input_rate + output_tokens / 1_000_000 * output_rate
  end

  def format_cost(cost) when cost < 0.01, do: "<$0.01"
  def format_cost(cost), do: "$#{:erlang.float_to_binary(cost, decimals: 2)}"

  def format_tokens(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}K"
  def format_tokens(n), do: "#{n}"
end
