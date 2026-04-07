defmodule Cortex.Terminal.ScrollbackTest do
  use ExUnit.Case, async: true

  alias Cortex.Terminal.Scrollback

  describe "new/0" do
    test "creates empty scrollback with defaults" do
      sb = Scrollback.new()
      assert sb.max_bytes == 256_000
      assert sb.buffer == []
      assert sb.size == 0
    end

    test "creates scrollback with custom max_bytes" do
      sb = Scrollback.new(1024)
      assert sb.max_bytes == 1024
    end
  end

  describe "push/2 and to_binary/1" do
    test "push adds data and to_binary returns it" do
      sb = Scrollback.new() |> Scrollback.push("hello")
      assert Scrollback.to_binary(sb) == "hello"
    end

    test "push accumulates multiple chunks in order" do
      sb =
        Scrollback.new()
        |> Scrollback.push("hello ")
        |> Scrollback.push("world")

      assert Scrollback.to_binary(sb) == "hello world"
    end

    test "to_binary on empty scrollback returns empty string" do
      sb = Scrollback.new()
      assert Scrollback.to_binary(sb) == ""
    end
  end

  describe "ring buffer trimming" do
    test "trims when exceeding max_bytes" do
      sb = Scrollback.new(10)

      sb =
        sb
        |> Scrollback.push("12345")
        |> Scrollback.push("67890")
        |> Scrollback.push("ABCDE")

      result = Scrollback.to_binary(sb)
      # After pushing 15 bytes into a 10 byte buffer, only last 10 should remain
      assert byte_size(result) == 10
      assert result == "67890ABCDE"
    end

    test "exact max_bytes does not trim" do
      sb = Scrollback.new(10) |> Scrollback.push("1234567890")
      assert Scrollback.to_binary(sb) == "1234567890"
      assert sb.size == 10
    end
  end

  describe "disk persistence" do
    setup do
      session_id = "test-scrollback-#{System.unique_integer([:positive])}"

      on_exit(fn ->
        Scrollback.delete_from_disk(session_id)
      end)

      %{session_id: session_id}
    end

    test "save_to_disk writes file, load_from_disk reads it back", %{session_id: session_id} do
      sb = Scrollback.new() |> Scrollback.push("persisted data")
      assert :ok = Scrollback.save_to_disk(sb, session_id)
      assert Scrollback.load_from_disk(session_id) == "persisted data"
    end

    test "load_from_disk returns nil for non-existent session" do
      assert Scrollback.load_from_disk("nonexistent-session-id-999") == nil
    end

    test "delete_from_disk removes the file", %{session_id: session_id} do
      sb = Scrollback.new() |> Scrollback.push("to delete")
      Scrollback.save_to_disk(sb, session_id)
      assert Scrollback.load_from_disk(session_id) != nil

      assert :ok = Scrollback.delete_from_disk(session_id)
      assert Scrollback.load_from_disk(session_id) == nil
    end

    test "roundtrip: push -> save -> load matches original", %{session_id: session_id} do
      data = "line 1\nline 2\nline 3\n"

      sb =
        Scrollback.new()
        |> Scrollback.push("line 1\n")
        |> Scrollback.push("line 2\n")
        |> Scrollback.push("line 3\n")

      Scrollback.save_to_disk(sb, session_id)
      loaded = Scrollback.load_from_disk(session_id)

      assert loaded == data
      assert loaded == Scrollback.to_binary(sb)
    end
  end
end
