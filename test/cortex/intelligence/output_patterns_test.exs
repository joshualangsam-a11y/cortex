defmodule Cortex.Intelligence.OutputPatternsTest do
  use ExUnit.Case, async: true

  alias Cortex.Intelligence.OutputPatterns

  describe "detect/1" do
    test "detects CompileError as build_error with :error severity" do
      output = ~s|** (CompileError) lib/my_app.ex:10: undefined function foo/0|
      [match | _] = OutputPatterns.detect(output)
      assert match.type == :build_error
      assert match.severity == :error
      assert match.message =~ "Compile error"
    end

    test "detects SyntaxError as build_error" do
      output = ~s|** (SyntaxError) lib/my_app.ex:5: unexpected token: "|
      [match | _] = OutputPatterns.detect(output)
      assert match.type == :build_error
      assert match.severity == :error
      assert match.message =~ "Syntax error"
    end

    test "detects BUILD FAILED as build_error" do
      output = "BUILD FAILED\nsome error details"
      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)
      assert :build_error in types

      failed_match = Enum.find(matches, &(&1.message =~ "Build failed"))
      assert failed_match.severity == :error
    end

    test "detects test pass with 0 failures as test_success" do
      output = "5 tests, 0 failures"
      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)
      assert :test_success in types

      success = Enum.find(matches, &(&1.type == :test_success))
      assert success.severity == :success
    end

    test "detects test failures as test_failure with :error severity" do
      output = "5 tests, 2 failures"
      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)
      assert :test_failure in types

      failure = Enum.find(matches, &(&1.type == :test_failure))
      assert failure.severity == :error
    end

    test "detects deploy succeeded as deploy_success" do
      output = "deploy succeeded at 2024-01-01"
      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)
      assert :deploy_success in types

      deploy = Enum.find(matches, &(&1.type == :deploy_success))
      assert deploy.severity == :success
    end

    test "detects deploy failed as deploy_failure with :error severity" do
      output = "deploy failed: timeout"
      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)
      assert :deploy_failure in types

      deploy = Enum.find(matches, &(&1.type == :deploy_failure))
      assert deploy.severity == :error
    end

    test "detects CONFLICT as git_conflict with :warning severity" do
      output = "CONFLICT (content): Merge conflict in lib/app.ex"
      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)
      assert :git_conflict in types

      conflict = Enum.find(matches, &(&1.type == :git_conflict))
      assert conflict.severity == :warning
    end

    test "detects server start pattern with :info severity" do
      output = "Running CortexWeb.Endpoint at http://localhost:3012"
      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)
      assert :server_started in types

      server = Enum.find(matches, &(&1.type == :server_started))
      assert server.severity == :info
    end

    test "returns empty list for plain text with no patterns" do
      output = "just some regular output with no special patterns"
      assert OutputPatterns.detect(output) == []
    end

    test "handles empty string input" do
      assert OutputPatterns.detect("") == []
    end

    test "handles non-binary input" do
      assert OutputPatterns.detect(nil) == []
      assert OutputPatterns.detect(123) == []
    end

    test "handles binary with multiple patterns and returns all matches" do
      output = """
      ** (CompileError) lib/app.ex:1: error
      5 tests, 2 failures
      CONFLICT (content): Merge conflict
      """

      matches = OutputPatterns.detect(output)
      types = Enum.map(matches, & &1.type)

      assert :build_error in types
      assert :test_failure in types
      assert :git_conflict in types
      assert length(matches) >= 3
    end
  end
end
