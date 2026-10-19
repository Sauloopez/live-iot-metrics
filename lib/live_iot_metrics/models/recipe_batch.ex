defmodule LiveMetrics.Models.RecipeBatch do
  alias LiveMetrics.Models.{AreaBatch, BatchSensor, Recipes}
  alias LiveMetrics.Repo
  use LiveMetrics.BaseSchema
  import Ecto.Query
  import Ecto.Changeset

  schema "recipe_batch" do
    field :name, :string
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :recipe, Recipes, foreign_key: :recipe_id
    has_many :batch_sensors, BatchSensor
    has_one :area_batch, AreaBatch, foreign_key: :batch_id
  end

  def changeset(recipe_batch, attrs) do
    recipe_batch
    |> cast(attrs, [:name, :started_at, :ended_at, :recipe_id])
    |> validate_required([:name, :started_at, :recipe_id])
    |> cast_assoc(:area_batch, required: true)
  end

  def find_all_active_by_area(area_id) do
    query =
      from u in __MODULE__,
        join: b in assoc(u, :area_batch),
        on: u.id == b.batch_id,
        join: r in assoc(u, :recipe),
        on: u.recipe_id == r.id,
        left_join: s in assoc(u, :batch_sensors),
        on: u.id == s.recipe_batch_id,
        where: b.area_id == ^area_id and is_nil(u.ended_at),
        preload: [recipe: r, batch_sensors: s]

    Repo.all(query, [])
  end

  def find_by_id(batch_id) do
    Repo.one(
      from u in __MODULE__,
        join: b in assoc(u, :area_batch),
        on: u.id == b.batch_id,
        join: r in assoc(u, :recipe),
        on: u.recipe_id == r.id,
        left_join: s in assoc(u, :batch_sensors),
        on: u.id == s.recipe_batch_id,
        left_join: bs in assoc(s, :sensor),
        on: bs.id == s.sensor_id,
        left_join: nd in assoc(bs, :node),
        on: nd.id == bs.node_id,
        where: u.id == ^batch_id,
        preload: [
          recipe: {r, :property_ranges},
          batch_sensors: {s, sensor: {bs, node: nd}}
        ]
    )
  end

  def create(recipe_batch, attrs) do
    recipe_batch
    |> changeset(attrs)
    |> Repo.insert()
  end
end
