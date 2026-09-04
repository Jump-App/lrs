defmodule LRS.Pure do
  @moduledoc """
  Pure-Elixir longest repeating substring.

  Strategy: same suffix-array-by-sorting idea as the Rust NIF, but leaning on
  the pieces of the BEAM that are already native C:

    * `binary_part/3` on a refc binary makes an O(1) *sub-binary* that shares
      the original bytes, so the list of all N suffixes costs O(N) small heap
      terms, not O(N^2) bytes.
    * `:lists.sort/1` compares binaries with the VM's native byte comparison
      (memcmp-style), and UTF-8 byte order == code point order, so the sorted
      order matches the Rust `Vec<char>` sort.
    * `:binary.longest_common_prefix/1` is a BIF, so the LCP of each adjacent
      pair in the sorted array is computed in C.

  Lengths are measured in bytes and the winner is trimmed back to a UTF-8
  character boundary, so on multibyte text the tie-breaking can in principle
  differ from the NIF (which measures in code points).
  """

  def longest_repeating_substring(""), do: ""

  def longest_repeating_substring(s) when is_binary(s) do
    n = byte_size(s)
    suffixes = build_suffixes(s, n - 1, [])
    sorted = :lists.sort(suffixes)
    {_best_chars, best} = scan(sorted, 0, "")
    best
  end

  @doc "Older variant that measures length in bytes rather than code points (kept for comparison)."
  def longest_repeating_substring_bytes(""), do: ""

  def longest_repeating_substring_bytes(s) when is_binary(s) do
    n = byte_size(s)
    sorted = :lists.sort(build_suffixes(s, n - 1, []))
    {best_len, best_suffix} = scan_bytes(sorted, 0, "")
    best_len = trim_to_char_boundary(best_suffix, best_len)
    binary_part(best_suffix, 0, best_len)
  end

  # Build [suffix(0), suffix(1), ...] by consing from the back so no reverse is needed.
  # Only offsets on a UTF-8 character boundary become suffixes, matching the NIF's
  # suffix array over Vec<char>; a continuation byte (10xxxxxx) is skipped.
  defp build_suffixes(_s, i, acc) when i < 0, do: acc

  defp build_suffixes(s, i, acc) do
    case s do
      <<_::binary-size(^i), 0b10::2, _::bits>> -> build_suffixes(s, i - 1, acc)
      _ -> build_suffixes(s, i - 1, [binary_part(s, i, byte_size(s) - i) | acc])
    end
  end

  # Walk adjacent pairs of the sorted suffix array; keep the first strict maximum
  # measured in code points, exactly like the NIF's LCP scan over Vec<char>.
  # The byte LCP is an upper bound on the code-point LCP, so we only pay for an
  # exact count when the byte LCP could beat the current best.
  defp scan([a, b | rest], best_chars, best) do
    bytes = :binary.longest_common_prefix([a, b])

    if bytes > best_chars do
      bytes = trim_to_char_boundary(a, bytes)
      chars = count_codepoints(binary_part(a, 0, bytes), 0)

      if chars > best_chars,
        do: scan([b | rest], chars, binary_part(a, 0, bytes)),
        else: scan([b | rest], best_chars, best)
    else
      scan([b | rest], best_chars, best)
    end
  end

  defp scan(_, best_chars, best), do: {best_chars, best}

  defp count_codepoints(<<_::utf8, rest::binary>>, n), do: count_codepoints(rest, n + 1)
  defp count_codepoints(<<>>, n), do: n

  defp scan_bytes([a, b | rest], best_len, best) do
    len = :binary.longest_common_prefix([a, b])

    if len > best_len,
      do: scan_bytes([b | rest], len, a),
      else: scan_bytes([b | rest], best_len, best)
  end

  defp scan_bytes(_, best_len, best), do: {best_len, best}

  # Back off (at most 3 bytes) so we never cut inside a multibyte code point.
  defp trim_to_char_boundary(_bin, 0), do: 0

  defp trim_to_char_boundary(bin, len) when len >= byte_size(bin), do: len

  defp trim_to_char_boundary(bin, len) do
    case bin do
      <<_::binary-size(^len), 0b10::2, _::bits>> -> trim_to_char_boundary(bin, len - 1)
      _ -> len
    end
  end

  # ---------------------------------------------------------------------------
  # Threshold-aware variant: the real API (`recursively_remove_repeating_substring`)
  # only cares about repeats longer than `min_len`. Any two suffixes sharing a
  # repeat of length >= k share their first k bytes, so we can bucket suffixes by
  # their k-byte prefix in a map, discard singleton buckets (the vast majority for
  # natural-language text), and only sort + LCP-scan the survivors.
  # Returns "" when no repeat of at least `min_len` bytes exists.
  # ---------------------------------------------------------------------------
  def longest_repeating_substring_at_least(s, min_len) when is_binary(s) and min_len >= 1 do
    n = byte_size(s)

    if n < 2 * min_len do
      ""
    else
      buckets = bucket(s, n - min_len, min_len, %{})

      candidates =
        for {_k, [_, _ | _] = group} <- buckets, reduce: [] do
          acc -> Enum.reverse(group, acc)
        end

      {best_len, best_suffix} = scan_bytes(:lists.sort(candidates), min_len - 1, "")
      best_len = trim_to_char_boundary(best_suffix, best_len)
      if best_len >= min_len, do: binary_part(best_suffix, 0, best_len), else: ""
    end
  end

  defp bucket(_s, i, _k, acc) when i < 0, do: acc

  defp bucket(s, i, k, acc) do
    suffix = binary_part(s, i, byte_size(s) - i)
    key = binary_part(suffix, 0, k)
    bucket(s, i - 1, k, Map.update(acc, key, [suffix], &[suffix | &1]))
  end

  def recursively_remove_repeating_substring(string, above_size \\ 30)
  def recursively_remove_repeating_substring("", _), do: ""

  def recursively_remove_repeating_substring(string, above_size) do
    longest = longest_repeating_substring(string)

    if String.length(longest) > above_size do
      new_string = String.replace(string, longest, " ", global: false)

      if new_string != string,
        do: recursively_remove_repeating_substring(new_string, above_size),
        else: string
    else
      string
    end
  end
end
