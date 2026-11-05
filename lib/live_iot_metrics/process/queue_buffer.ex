defmodule LiveMetrics.QueueBuffer do
  @moduledoc """
  Queue that processes requests in the background and in batches, so the CoAP handler that
  enqueues them answers right away instead of waiting for the database.

      defmodule MyBuffer do
        use LiveMetrics.QueueBuffer, flush_interval_ms: 1000, max_batch: 20

        @impl LiveMetrics.QueueBuffer
        def process_batch(items), do: ...
      end

      MyBuffer.enqueue(item)

  A batch is processed when `max_batch` items are queued or every `flush_interval_ms`. Only
  one batch runs at a time, so items are processed in the order they arrived.
  """

  @doc "Processes a batch of items (runs in a task, in arrival order)."
  @callback process_batch([term()]) :: any()

  @doc "Optional: runs once when the buffer starts (e.g. to create an ETS table)."
  @callback setup() :: any()
  @optional_callbacks setup: 0

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use GenServer
      require Logger
      @behaviour LiveMetrics.QueueBuffer

      @flush_interval_ms Keyword.get(opts, :flush_interval_ms, 1000)
      @max_batch Keyword.get(opts, :max_batch, 20)

      def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

      def enqueue(item), do: GenServer.cast(__MODULE__, {:enqueue, item})

      @doc "Processes everything queued and waits for it (tests and shutdown)."
      def drain, do: GenServer.call(__MODULE__, :drain, 30_000)

      @impl GenServer
      def init(nil) do
        if function_exported?(__MODULE__, :setup, 0), do: apply(__MODULE__, :setup, [])
        schedule_flush()
        {:ok, %{queue: [], count: 0, running: nil, waiting: []}}
      end

      @impl GenServer
      def handle_cast({:enqueue, item}, state) do
        state = %{state | queue: [item | state.queue], count: state.count + 1}
        {:noreply, if(state.count >= @max_batch, do: run_next(state), else: state)}
      end

      @impl GenServer
      def handle_call(:drain, from, state) do
        state = run_next(state)

        if idle?(state),
          do: {:reply, :ok, state},
          else: {:noreply, %{state | waiting: [from | state.waiting]}}
      end

      @impl GenServer
      def handle_info(:flush, state) do
        schedule_flush()
        {:noreply, run_next(state)}
      end

      def handle_info({ref, _result}, %{running: ref} = state) do
        Process.demonitor(ref, [:flush])
        {:noreply, batch_finished(state)}
      end

      def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: ref} = state) do
        Logger.error("#{inspect(__MODULE__)} batch crashed: #{inspect(reason)}")
        {:noreply, batch_finished(state)}
      end

      def handle_info(_msg, state), do: {:noreply, state}

      defp batch_finished(state) do
        state = run_next(%{state | running: nil})

        if idle?(state) do
          Enum.each(state.waiting, &GenServer.reply(&1, :ok))
          %{state | waiting: []}
        else
          state
        end
      end

      defp run_next(%{running: nil, queue: [_ | _]} = state) do
        batch = Enum.reverse(state.queue)
        task = Task.async(fn -> process_batch(batch) end)
        %{state | queue: [], count: 0, running: task.ref}
      end

      defp run_next(state), do: state

      defp idle?(state), do: state.running == nil and state.queue == []

      defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval_ms)
    end
  end
end
