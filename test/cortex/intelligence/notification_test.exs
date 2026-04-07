defmodule Cortex.Intelligence.NotificationTest do
  use ExUnit.Case, async: true

  alias Cortex.Intelligence.Notification

  describe "struct" do
    test "creates struct with all fields" do
      now = DateTime.utc_now()

      notification = %Notification{
        id: "abc-123",
        session_id: "session-1",
        type: :build_error,
        severity: :error,
        message: "Compile error",
        timestamp: now
      }

      assert notification.id == "abc-123"
      assert notification.session_id == "session-1"
      assert notification.type == :build_error
      assert notification.severity == :error
      assert notification.message == "Compile error"
      assert notification.timestamp == now
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Notification, %{id: "1"})
      end
    end
  end

  describe "from_match/2" do
    test "builds notification from pattern match result" do
      match = %{type: :test_failure, severity: :error, message: "Test failures detected"}
      notification = Notification.from_match("session-42", match)

      assert notification.session_id == "session-42"
      assert notification.type == :test_failure
      assert notification.severity == :error
      assert notification.message == "Test failures detected"
      assert is_binary(notification.id)
      assert %DateTime{} = notification.timestamp
    end

    test "generates unique IDs for each notification" do
      match = %{type: :build_error, severity: :error, message: "Build failed"}

      n1 = Notification.from_match("s1", match)
      n2 = Notification.from_match("s1", match)

      assert n1.id != n2.id
    end
  end
end
