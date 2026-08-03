defmodule ExBlog.Repo.Migrations.CreateExBlogRuntimeTables do
  use Ecto.Migration

  def change do
    create table(:spectre_states, primary_key: false) do
      add :conversation_id, :string, primary_key: true
      add :agent, :string, primary_key: true
      add :revision, :integer, null: false, default: 0
      add :payload, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:spectre_memory) do
      add :agent, :string, null: false
      add :cue, :text, null: false
      add :embedding, {:array, :float}
      add :label, :string, null: false
      add :verified, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:spectre_memory, [:agent, :updated_at])

    create table(:spectre_journal) do
      add :conversation_id, :string, null: false
      add :event, :string, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:spectre_journal, [:conversation_id, :inserted_at])

    create table(:llm_usage) do
      add :occurred_at, :utc_datetime_usec, null: false
      add :purpose, :string, null: false
      add :level, :string, null: false
      add :model, :string, null: false
      add :prompt_tokens, :integer, null: false, default: 0
      add :completion_tokens, :integer, null: false, default: 0
      add :cost_usd, :decimal, null: false, default: 0
      add :cost_eur, :decimal, null: false, default: 0
      add :subject_type, :string
      add :subject_ref, :string
      add :conversation_id, :string

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:llm_usage, [:occurred_at])
    create index(:llm_usage, [:model, :occurred_at])
    create index(:llm_usage, [:subject_type, :subject_ref])

    create table(:budget_periods, primary_key: false) do
      add :period, :string, primary_key: true
      add :spent_eur, :decimal, null: false, default: 0
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:git_operations) do
      add :op, :string, null: false
      add :commit_sha, :string
      add :files, :map, null: false, default: %{}
      add :ok, :boolean, null: false
      add :error, :text

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:git_operations, [:inserted_at])

  end
end
