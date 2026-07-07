defmodule LiveMetrics.Metrics.Processor do
  alias LiveMetrics.Repo
  require Logger

  def process_batch(metrics) do
    case Repo.query("SELECT insert_reading_in_batch($1)", [metrics]) do
      {:ok, _result} ->
        Logger.info("Inserted #{Enum.count(metrics)} readings into the database")

      {:error, reason} ->
        Logger.error("Error inserting batch into Postgres: #{inspect(reason)}")
    end
  end
end
