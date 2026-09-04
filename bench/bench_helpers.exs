defmodule Bench do
  def rss_kb do
    {out, 0} = System.cmd("ps", ["-o", "rss=", "-p", "#{:os.getpid()}"])
    out |> String.trim() |> String.to_integer()
  end

  # Runs fun in a fresh process; samples OS RSS and the process heap every 20ms.
  # Returns {microseconds, peak_rss_delta_mb, peak_proc_heap_mb, result}
  def measure(fun) do
    :erlang.garbage_collect()
    base_rss = rss_kb()
    parent = self()
    pid = spawn(fn -> send(parent, {:done, :timer.tc(fun)}) end)
    sample(pid, base_rss, 0, 0)
  end

  defp sample(pid, base_rss, peak_rss, peak_heap) do
    receive do
      {:done, {us, result}} ->
        {us, peak_rss / 1024, peak_heap / 1_048_576, result}
    after
      20 ->
        heap =
          case Process.info(pid, :memory) do
            {:memory, m} -> m
            _ -> 0
          end

        sample(pid, base_rss, max(peak_rss, rss_kb() - base_rss), max(peak_heap, heap))
    end
  end

  def stats(list) do
    sorted = Enum.sort(list)
    {Enum.min(sorted), Enum.at(sorted, div(length(sorted), 2))}
  end

  def ms(us), do: :erlang.float_to_binary(us / 1000, decimals: 1)
  def mb(x), do: :erlang.float_to_binary(x * 1.0, decimals: 1)
end
