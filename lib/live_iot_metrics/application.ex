defmodule LiveMetrics.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LiveMetricsWeb.Telemetry,
      LiveMetrics.Repo,
      {DNSCluster, query: Application.get_env(:live_iot_metrics, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LiveMetrics.PubSub},
      # Start a worker by calling: LiveMetrics.Worker.start_link(arg)
      # {LiveMetrics.Worker, arg},
      LiveMetrics.Coap.Server,
      # Start to serve requests, typically the last entry
      LiveMetricsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LiveMetrics.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiveMetricsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
