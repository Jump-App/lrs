defmodule LRSPureParityTest do
  @moduledoc "Pins LRS.Pure (sieve + incremental removal) to the NIF's exact answers."
  use ExUnit.Case, async: true

  # Small alphabets make overlapping repeats common; multibyte characters exercise
  # the code-point tie-breaking and character-boundary handling.
  @alphabets [~w(a b), ~w(a b c), ~w(a b c d e f g h), ~w(a é 🐳 b), ["a", "b", " ", "x", "ü"]]

  defp rand_string(alpha, len), do: Enum.map_join(1..len//1, fn _ -> Enum.random(alpha) end)

  # Random chunks plus a few long segments planted 2-3 times each.
  defp planted(alpha) do
    chunks = for _ <- 1..Enum.random(5..40), do: rand_string(alpha, Enum.random(1..80))

    repeats =
      for _ <- 1..Enum.random(0..4)//1 do
        r = rand_string(alpha, Enum.random(20..120))
        List.duplicate(r, Enum.random(2..3))
      end

    Enum.join(Enum.shuffle(chunks ++ List.flatten(repeats)))
  end

  defp assert_parity(s) do
    nif = LRS.longest_repeating_substring(s)
    assert LRS.Pure.longest_repeating_substring(s) == nif
    assert LRS.Pure.longest_repeating_substring(s, workers: 3) == nif
    assert LRS.Pure.longest_repeating_substring_full(s) == nif

    for min_chars <- [1, 2, 3, 5, 8, 13, 31, 64] do
      expected = if String.length(nif) >= min_chars, do: nif, else: ""
      assert LRS.Pure.longest_repeating_substring_at_least(s, min_chars) == expected
    end

    # Tiny thresholds mean one removal per repeated character; keep those to short inputs.
    thresholds = if byte_size(s) <= 300, do: [0, 1, 2, 4, 10, 30], else: [10, 30]

    for above <- thresholds do
      expected = LRS.recursively_remove_repeating_substring(s, above)
      assert LRS.Pure.recursively_remove_repeating_substring(s, above) == expected
      assert LRS.Pure.recursively_remove_repeating_substring(s, above, workers: 4) == expected
    end
  end

  test "overlapping and degenerate repeats" do
    for s <- [
          "a",
          "aa",
          "aaa",
          "aaaaa",
          "abababab",
          String.duplicate("a", 100),
          String.duplicate("ab", 100),
          String.duplicate("🐳", 40),
          "x🐳🐳🐳y"
        ] do
      assert_parity(s)
    end
  end

  test "threshold is measured in characters, so multibyte repeats cannot win a tie by bytes" do
    # "a" and "🐳" both repeat and are 1 character long; the NIF picks "a" (first in
    # sorted order). A 3-byte threshold must not switch the answer to "🐳".
    s = "bbaa🐳é🐳🐳a"
    assert LRS.longest_repeating_substring(s) == "a"
    assert LRS.Pure.longest_repeating_substring_at_least(s, 3) == ""
    assert_parity(s)
  end

  test "results are copied rather than sub-binaries pinning the input" do
    s = :crypto.strong_rand_bytes(4_000) |> Base.encode16() |> Kernel.<>("repeat me!repeat me!")

    for result <- [
          LRS.Pure.longest_repeating_substring(s),
          LRS.Pure.longest_repeating_substring_at_least(s, 5),
          LRS.Pure.longest_repeating_substring_full(s)
        ] do
      assert result == "repeat me!"
      assert :binary.referenced_byte_size(result) == byte_size(result)
    end
  end

  test "random inputs match the NIF" do
    :rand.seed(:exsss, {2026, 9, 4})

    for i <- 1..300 do
      alpha = Enum.random(@alphabets)

      s =
        case rem(i, 3) do
          0 -> rand_string(alpha, Enum.random(1..12))
          1 -> rand_string(alpha, Enum.random(1..300))
          2 -> planted(alpha)
        end

      assert_parity(s)
    end
  end
end
