defmodule LiveMetrics.Repo.Migrations.RecipesAreas do
  use Ecto.Migration

  def change do
    create table("area_batches", primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :area_id, references("areas", on_delete: :delete_all, type: :binary_id), null: false
      add :batch_id, references("recipe_batch", on_delete: :delete_all, type: :binary_id),
        null: false
      timestamps()
    end

    create unique_index("area_batches", [:area_id, :recipe_id])
  end
end
