defmodule LiveMetrics.Models.AreaBatch do
  use LiveMetrics.BaseSchema

  schema "area_batches" do
    belongs_to :area, LiveMetrics.Models.Area, foreign_key: :area_id
    belongs_to :batch, LiveMetrics.Models.RecipeBatch, foreign_key: :batch_id
  end
end
