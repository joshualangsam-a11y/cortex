defmodule Cortex.Repo.Migrations.AddStripeFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :subscription_status, :string, default: "incomplete"
      add :trial_ends_at, :utc_datetime
    end

    create unique_index(:users, [:stripe_customer_id])
  end
end
