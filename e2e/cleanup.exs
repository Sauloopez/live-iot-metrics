# Deletes the data created by the end-to-end tests, so every run starts clean:
#   * nodes with a simulated MAC (02:00:00:00:E2:*) with their sensors and readings,
#     sync states, status reports and saved sensor configurations
#   * areas and reading definitions whose name starts with "e2e-" (their readings cascade)
#
# Run from the project root: mix run --no-start e2e/cleanup.exs
Logger.configure(level: :warning)
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sql)
{:ok, _} = LiveMetrics.Repo.start_link()

alias LiveMetrics.Repo

fake_mac = "02:00:00:00:E2:%"

counts =
  for {label, sql} <- [
        {"nodes", "DELETE FROM nodes WHERE mac LIKE $1"},
        {"sync states", "DELETE FROM node_sync_states WHERE mac LIKE $1"},
        {"status reports", "DELETE FROM node_status_reports WHERE mac LIKE $1"},
        {"sensor configs", "DELETE FROM node_sensor_configs WHERE mac LIKE $1"}
      ] do
    %{num_rows: n} = Repo.query!(sql, [fake_mac])
    "#{n} #{label}"
  end

%{num_rows: areas} = Repo.query!("DELETE FROM areas WHERE name LIKE 'e2e-%'")
%{num_rows: recipes} = Repo.query!("DELETE FROM recipes WHERE name LIKE 'e2e-%'")

IO.puts(
  "e2e cleanup: " <> Enum.join(counts ++ ["#{areas} areas", "#{recipes} definitions"], ", ")
)
