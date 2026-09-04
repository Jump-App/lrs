text = File.read!(Path.join(__DIR__, "moby.txt"))

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

impls = [
  {"Rust NIF", &LRS.longest_repeating_substring/1},
  {"Elixir: suffix sort", &LRS.Pure.longest_repeating_substring/1},
  {"Elixir: bucketed, min 31 bytes", &LRS.Pure.longest_repeating_substring_at_least(&1, 31)}
]

sizes = [10_000, 50_000, 100_000, 250_000, 500_000, String.length(text)]
runs = 5

# warm-up
for {_, f} <- impls, do: f.(String.slice(text, 0, 20_000))

IO.puts("## longest_repeating_substring/1 on Moby Dick prefixes (#{runs} runs each, Apple M4 Max)\n")
IO.puts("| chars | impl | min ms | median ms | vs NIF (median) | peak RSS growth MB | peak proc heap MB | result |")
IO.puts("|---|---|---|---|---|---|---|---|")

for size <- sizes do
  slice = String.slice(text, 0, size)

  rows =
    for {name, f} <- impls do
      samples = for _ <- 1..runs, do: Bench.measure(fn -> f.(slice) end)
      {min_us, med_us} = Bench.stats(Enum.map(samples, &elem(&1, 0)))
      rss = samples |> Enum.map(&elem(&1, 1)) |> Enum.max()
      heap = samples |> Enum.map(&elem(&1, 2)) |> Enum.max()
      {name, min_us, med_us, rss, heap, elem(hd(samples), 3)}
    end

  {_, _, nif_med, _, _, nif_result} = hd(rows)

  for {name, min_us, med_us, rss, heap, result} <- rows do
    same =
      cond do
        result == nif_result -> "same as NIF"
        String.length(result) == String.length(nif_result) -> "same length, different text"
        true -> "DIFFERENT (#{String.length(result)} vs #{String.length(nif_result)} chars)"
      end

    IO.puts(
      "| #{size} | #{name} | #{Bench.ms(min_us)} | #{Bench.ms(med_us)} | #{:erlang.float_to_binary(med_us / nif_med, decimals: 2)}x | #{Bench.mb(rss)} | #{Bench.mb(heap)} | #{same}; #{String.length(result)} chars |"
    )
  end
end

IO.puts(
  "\nLongest repeat in the full text (first 60 chars): #{inspect(String.slice(hd(for {_, f} <- impls, do: f.(text)), 0, 60))}"
)

# ---------------------------------------------------------------------------
IO.puts("\n## recursively_remove_repeating_substring/2 (threshold 30)\n")

count_iterations = fn string, above ->
  Stream.unfold(string, fn s ->
    longest = LRS.longest_repeating_substring(s)

    if String.length(longest) > above do
      ns = String.replace(s, longest, " ", global: false)
      if ns != s, do: {ns, ns}, else: nil
    else
      nil
    end
  end)
  |> Enum.count()
end

IO.puts("| chars | iterations | impl | ms | vs NIF | peak RSS growth MB | same output |")
IO.puts("|---|---|---|---|---|---|---|")

for size <- [100_000, 500_000, String.length(text)] do
  slice = String.slice(text, 0, size)
  iters = count_iterations.(slice, 30)

  {nif_us, nif_rss, _, nif_out} = Bench.measure(fn -> LRS.recursively_remove_repeating_substring(slice, 30) end)
  {pure_us, pure_rss, _, pure_out} = Bench.measure(fn -> LRS.Pure.recursively_remove_repeating_substring(slice, 30) end)

  IO.puts("| #{size} | #{iters} | Rust NIF | #{Bench.ms(nif_us)} | 1.00x | #{Bench.mb(nif_rss)} | - |")

  IO.puts(
    "| #{size} | #{iters} | Elixir: bucketed | #{Bench.ms(pure_us)} | #{:erlang.float_to_binary(pure_us / nif_us, decimals: 2)}x | #{Bench.mb(pure_rss)} | #{pure_out == nif_out} |"
  )
end
