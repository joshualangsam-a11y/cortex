defmodule Cortex.Terminals.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "terminal_sessions" do
    field :title, :string
    field :command, :string, default: "/bin/zsh"
    field :cwd, :string
    field :project_name, :string
    field :status, :string, default: "running"
    field :exit_code, :integer
    field :cols, :integer, default: 120
    field :rows, :integer, default: 30
    field :started_at, :utc_datetime
    field :exited_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :title,
      :command,
      :cwd,
      :project_name,
      :status,
      :exit_code,
      :cols,
      :rows,
      :started_at,
      :exited_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, ~w(running exited))
  end
end
