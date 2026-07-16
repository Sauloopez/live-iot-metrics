defmodule LiveMetrics.Models.AreaBatch do
  use LiveMetrics.BaseSchema
  import Ecto.{Changeset}

  schema "area_batches" do
    belongs_to :area, LiveMetrics.Models.Area, foreign_key: :area_id
    belongs_to :batch, LiveMetrics.Models.RecipeBatch, foreign_key: :batch_id

    timestamps()
  end

  def changeset(area_batch, attrs) do
    area_batch
    |> cast(attrs, [:area_id, :batch_id])
    |> validate_required([:area_id, :batch_id])
  end
end
