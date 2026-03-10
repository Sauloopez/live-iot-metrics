defmodule LiveMetricsWeb.PageController do
  use LiveMetricsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
