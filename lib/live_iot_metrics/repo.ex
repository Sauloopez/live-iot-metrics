defmodule LiveMetrics.Repo do
  use Ecto.Repo,
    otp_app: :live_iot_metrics,
    adapter: Ecto.Adapters.Postgres
end
