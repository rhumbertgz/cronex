defmodule Cronex.Table do
  @moduledoc """
  This module represents a cron table.
  """

  use GenServer

  import Cronex.Job

  alias Cronex.Job

  # Interface functions
  @doc """
  Starts a `Cronex.Table` instance.

  `args` must contain a `:scheduler` with a valid `Cronex.Scheduler`.
  """
  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc false
  def add_job(pid, %Job{} = job) do
    GenServer.call(pid, {:add_job, job})
  end

  @doc false
  def get_jobs(pid) do
    GenServer.call(pid, :get_jobs)
  end

  # Callback functions
  def init(args) do
    if is_nil(args[:scheduler]), do: raise_scheduler_not_provided_error()

    GenServer.cast(self(), :init)

    state = %{scheduler: args[:scheduler],
              jobs: Map.new,
              timer: new_ping_timer()}

    {:ok, state}
  end

  def handle_cast(:init, %{scheduler: scheduler} = state) do
    new_state =
      scheduler.jobs
      |> Enum.reduce(state, fn(job, state) ->
        job = apply(scheduler, job, [])
        do_add_job(state, job)
      end)

    {:noreply, new_state}
  end

  def handle_call({:add_job, %Job{} = job}, _from, state) do
    new_state = do_add_job(state, job)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_jobs, _from, state) do
    {:reply, state[:jobs], state}
  end

  def handle_info(:ping, %{scheduler: scheduler} = state) do
    updated_timer = new_ping_timer()

    updated_jobs =
      for {id, job} <- state[:jobs], into: %{} do
        updated_job =
          if can_run?(job) do
             run(job, scheduler.job_supervisor)
          else
            job
          end

        {id, updated_job}
      end

    new_state = %{state | timer: updated_timer, jobs: updated_jobs}
    {:noreply, new_state}
  end

  # Private functions
  defp raise_scheduler_not_provided_error do
    raise ArgumentError, message: """
    No scheduler was provided when starting Cronex.Table.

    Please provide a Scheduler like so:

        Cronex.Table.start_link(scheduler: MyApp.Scheduler)
    """
  end

  defp do_add_job(state, %Job{} = job) do
    index = state[:jobs]
            |> Map.keys
            |> Enum.count
    put_in(state, [:jobs, index], job)
  end

  defp new_ping_timer() do
    Process.send_after(self(), :ping, ping_interval())
  end

  defp ping_interval do
    case Mix.env do
      :prod -> 60000
      :dev -> 60000
      :test -> 100
    end
  end
end
