defmodule Cortex.Terminals.BurstModeTest do
  use ExUnit.Case, async: true

  alias Cortex.Terminals.BurstMode

  describe "burst_config/1" do
    test "includes claude agent session for any project" do
      project = %{name: "test", path: "/tmp/nonexistent", type: "generic"}
      config = BurstMode.burst_config(project)

      agent_session = Enum.find(config, &(&1.title =~ "agent"))
      assert agent_session
      assert agent_session.command == "claude"
    end

    test "detects elixir project and includes server + iex + test" do
      # Create temp dir with mix.exs
      dir =
        Path.join(System.tmp_dir!(), "burst_test_elixir_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "mix.exs"), "")

      project = %{name: "elixir-app", path: dir, type: "elixir"}
      config = BurstMode.burst_config(project)

      titles = Enum.map(config, & &1.title)
      assert Enum.any?(titles, &(&1 =~ "server"))
      assert Enum.any?(titles, &(&1 =~ "iex"))
      assert Enum.any?(titles, &(&1 =~ "test"))
      assert Enum.any?(titles, &(&1 =~ "agent"))

      File.rm_rf!(dir)
    end

    test "detects nextjs project" do
      dir = Path.join(System.tmp_dir!(), "burst_test_next_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "package.json"), ~s|{"dependencies":{"next":"14"}}|)

      project = %{name: "next-app", path: dir, type: "nextjs"}
      config = BurstMode.burst_config(project)

      commands = Enum.map(config, & &1.command) |> Enum.filter(& &1)
      assert Enum.any?(commands, &(&1 =~ "dev"))

      File.rm_rf!(dir)
    end
  end
end
