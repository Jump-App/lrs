defmodule LRS.Pure do
  @moduledoc """
  Pure-Elixir longest repeating substring.

  ## Baseline: suffix array by sorting

  The straightforward approach (`longest_repeating_substring_full/1`) mirrors
  the Rust NIF: make every suffix, sort them, and take the longest common
  prefix (LCP) of some adjacent pair. It leans on the parts of the BEAM that are
  already native C:

    * `binary_part/3` on a refc binary makes an O(1) *sub-binary* that shares
      the original bytes, so the list of all N suffixes costs O(N) small heap
      terms, not O(N^2) bytes.
    * `:lists.sort/1` compares binaries with the VM's native byte comparison,
      and UTF-8 byte order == code point order, so the sorted order matches the
      Rust `Vec<char>` sort.
    * `:binary.longest_common_prefix/1` is a BIF.

  Sorting N suffixes still dominates (N log N comparisons in an Erlang merge
  loop) and the N sub-binaries plus sort scratch are the memory peak.

  ## Sieve: only sort suffixes that can start a long repeat

  Callers usually only care about *long* repeats (`recursively_remove_repeating_substring/2`
  ignores anything of `above_size` characters or less). For a threshold of `t`
  bytes we pick `m = (t + 1) div 2` so that `2m - 1 <= t`, and observe:

  Any repeat of length `>= 2m - 1` occurring at positions `p` and `q` fully
  contains an *anchor* (an m-gram starting at a multiple of `m`) inside the
  occurrence at `p`; the same m bytes then appear inside the occurrence at `q`,
  starting at some position `j` with `q <= j < q + m`. Symmetrically `p` is
  within `m` bytes of a position whose m-gram equals an anchor.

  So: put the N/m anchor m-grams in a map, probe every position's m-gram
  against it, and take as candidates only the `m` positions at or before each
  hit. Both occurrences of every repeat of at least `t` bytes are candidates,
  and because the sorted candidates are a sub-sequence of the full sorted
  suffix array, the first strict maximum LCP among adjacent candidates is the
  same substring the full algorithm would return (adjacent-LCP is a running
  minimum, so no earlier pair can tie it). On natural-language text this
  prunes >90% of suffixes before the sort.

  If no repeat of at least `t` characters exists, the sieve reports `""` and
  `longest_repeating_substring/1` falls back to the full sort.

  The probing pass is embarrassingly parallel over position ranges; pass
  `workers: n` to split it across `n` processes (each builds its own copy of
  the small anchor map rather than receiving a copy of it).

  ## Incremental removal

  `recursively_remove_repeating_substring/2` replaces one occurrence per
  iteration, which only changes the t-byte windows overlapping the edit. The
  candidate set is therefore carried across iterations: windows that overlapped
  the edit are dropped, positions after it are shifted, and the `t` new windows
  spanning the inserted space are re-searched in the whole string with
  `:binary.match/3` (C). Stale candidates (whose partner was removed) are
  harmless extras, so no other bookkeeping is needed.

  Candidates are kept in the sorted order of the previous iteration. An edit
  reorders only the few suffixes whose common prefix reached into it, so the
  re-sort is a near-linear natural merge instead of a full N log N sort.

  Lengths are compared in code points like the NIF, so results (including
  tie-breaking) match it on multibyte text.
  """

  # Threshold tried first by `longest_repeating_substring/1` before falling
  # back to sorting every suffix.
  @sieve_threshold 31

  @typedoc "`workers: n` splits the sieve's probing pass over `n` processes (default 1)."
  @type option :: {:workers, pos_integer()}

  @doc """
  Longest substring that occurs at least twice (occurrences may overlap).

  Returns the same result as the NIF: the first strict maximum in sorted suffix
  order, measured in code points.
  """
  @spec longest_repeating_substring(String.t(), [option]) :: String.t()
  def longest_repeating_substring(s, opts \\ [])
  def longest_repeating_substring("", _opts), do: ""

  def longest_repeating_substring(s, opts) when is_binary(s) do
    case longest_repeating_substring_at_least(s, @sieve_threshold, opts) do
      "" -> longest_repeating_substring_full(s)
      found -> found
    end
  end

  @doc """
  Longest repeating substring, provided it is at least `min_chars` characters
  long; `""` otherwise. Much cheaper than `longest_repeating_substring/1` for
  large `min_chars` because only suffixes that can start such a repeat are
  sorted.

  The threshold is in characters, not bytes, so that the result is exactly what
  `longest_repeating_substring/1` returns whenever that is long enough: a
  repeat of `min_chars` code points has at least `min_chars` bytes, which is
  what the sieve needs, and a shorter-in-bytes repeat can therefore never tie
  it in code points.
  """
  @spec longest_repeating_substring_at_least(String.t(), pos_integer(), [option]) :: String.t()
  def longest_repeating_substring_at_least(s, min_chars, opts \\ [])
      when is_binary(s) and is_integer(min_chars) and min_chars >= 1 do
    # A repeat of t bytes needs at least t + 1 bytes of text (occurrences may overlap).
    if byte_size(s) <= min_chars do
      ""
    else
      candidates = sieve_positions(s, min_chars, Keyword.get(opts, :workers, 1))
      {best, _sorted_positions} = best_among(s, candidates)
      if count_codepoints(best, 0) >= min_chars, do: best, else: ""
    end
  end

  @doc "Sorts every suffix. Exact for any input; O(N) memory, O(N log N) time."
  @spec longest_repeating_substring_full(String.t()) :: String.t()
  def longest_repeating_substring_full(""), do: ""

  def longest_repeating_substring_full(s) when is_binary(s) do
    n = byte_size(s)
    {best, _} = scan(:lists.sort(build_suffixes(s, n - 1, [])), n, 0, "", [])
    best
  end

  @doc """
  Repeatedly replaces the first occurrence of the longest repeating substring
  with a space, as long as that substring is longer than `above_size`
  characters.
  """
  @spec recursively_remove_repeating_substring(String.t(), non_neg_integer(), [option]) ::
          String.t()
  def recursively_remove_repeating_substring(string, above_size \\ 30, opts \\ [])
  def recursively_remove_repeating_substring("", _, _), do: ""

  def recursively_remove_repeating_substring(string, above_size, opts)
      when is_binary(string) and is_integer(above_size) do
    # A repeat of more than `above_size` characters has at least `above_size + 1` bytes.
    t = max(above_size + 1, 1)

    if byte_size(string) <= t do
      string
    else
      candidates = sieve_positions(string, t, Keyword.get(opts, :workers, 1))
      remove_loop(string, above_size, t, candidates)
    end
  end

  # `candidates` holds every position that can start a repeat of >= t bytes,
  # in (approximately) sorted-suffix order.
  defp remove_loop(s, above_size, t, candidates) do
    {best, sorted_positions} = best_among(s, candidates)

    if count_codepoints(best, 0) > above_size do
      {r, l} = :binary.match(s, best)
      <<prefix::binary-size(^r), _::binary-size(^l), rest::binary>> = s
      new_s = <<prefix::binary, " ", rest::binary>>

      if new_s == s,
        do: s,
        else: remove_loop(new_s, above_size, t, update_candidates(sorted_positions, new_s, r, l, t))
    else
      s
    end
  end

  # ---------------------------------------------------------------------------
  # Sieve
  # ---------------------------------------------------------------------------

  # Ascending list of positions (on UTF-8 character boundaries) that can start a
  # repeat of at least `t` bytes. Superset of the true set; see @moduledoc.
  defp sieve_positions(s, t, workers) do
    n = byte_size(s)
    m = div(t + 1, 2)
    # Highest position with a full m-gram after it, hence the highest probe.
    last = n - m

    if workers <= 1 or last < 4 * workers do
      anchors = build_anchors(s, 0, m, last, %{})
      collect_candidates(s, last, last, 0, m, anchors, 0, [])
    else
      chunk = div(last + workers, workers)

      0..(workers - 1)
      |> Enum.map(fn w -> {w * chunk, min(w * chunk + chunk - 1, last)} end)
      |> Enum.map(fn {lo, hi} ->
        Task.async(fn ->
          anchors = build_anchors(s, 0, m, last, %{})
          # Probe up to m - 1 positions past `hi` so a hit just above this
          # range still covers the candidates inside it.
          collect_candidates(s, min(hi + m - 1, last), hi, lo, m, anchors, 0, [])
        end)
      end)
      |> Enum.flat_map(&Task.await(&1, :infinity))
    end
  end

  # Map of m-gram -> 1 | 2 (occurrence count among anchors, capped at 2).
  defp build_anchors(s, a, m, last, acc) when a <= last do
    build_anchors(s, a + m, m, last, Map.update(acc, binary_part(s, a, m), 1, fn _ -> 2 end))
  end

  defp build_anchors(_s, _a, _m, _last, acc), do: acc

  # Walk from position `i` down to `lo`. A position is a hit when its m-gram
  # equals an anchor *other than itself*; every hit makes the next `m` positions
  # (itself included) candidates, of which only those `<= hi` are emitted.
  # Consing while walking backwards yields ascending order.
  defp collect_candidates(_s, i, _hi, lo, _m, _anchors, _pending, acc) when i < lo, do: acc

  defp collect_candidates(s, i, hi, lo, m, anchors, pending, acc) do
    pending =
      case :maps.find(binary_part(s, i, m), anchors) do
        {:ok, 2} -> m
        {:ok, 1} -> if rem(i, m) == 0, do: pending, else: m
        :error -> pending
      end

    if pending > 0 do
      acc = if i > hi or continuation_byte?(s, i), do: acc, else: [i | acc]
      collect_candidates(s, i - 1, hi, lo, m, anchors, pending - 1, acc)
    else
      collect_candidates(s, i - 1, hi, lo, m, anchors, 0, acc)
    end
  end

  # Longest repeat among the suffixes starting at `positions` (first strict max
  # in sorted order, measured in code points), plus the positions in sorted
  # order with duplicates removed.
  defp best_among(s, positions) do
    n = byte_size(s)
    suffixes = for i <- positions, do: binary_part(s, i, n - i)
    scan(:lists.sort(suffixes), n, 0, "", [])
  end

  # ---------------------------------------------------------------------------
  # Incremental candidate maintenance for recursively_remove_repeating_substring
  # ---------------------------------------------------------------------------

  # `l` bytes at `r` were replaced by a single space, giving `new_s`.
  defp update_candidates(candidates, new_s, r, l, t) do
    n = byte_size(new_s)
    # Windows starting in [lo, r] now span the inserted space; their contents
    # changed, so they are re-derived below. Windows starting inside the removed
    # region are gone. Everything after shifts left by l - 1.
    lo = max(r - t + 1, 0)
    kept = shift_positions(candidates, lo, r + l, l - 1, [])
    fresh = occurrences_of_windows(new_s, lo, min(r, n - t), t)
    # `fresh` may repeat positions already in `kept`; `scan/5` drops duplicates.
    fresh ++ kept
  end

  # Order-preserving.
  defp shift_positions([i | rest], lo, hi, delta, acc) when i < lo,
    do: shift_positions(rest, lo, hi, delta, [i | acc])

  defp shift_positions([i | rest], lo, hi, delta, acc) when i < hi,
    do: shift_positions(rest, lo, hi, delta, acc)

  defp shift_positions([i | rest], lo, hi, delta, acc),
    do: shift_positions(rest, lo, hi, delta, [i - delta | acc])

  defp shift_positions([], _lo, _hi, _delta, acc), do: :lists.reverse(acc)

  # Every position in `s` (ascending) where one of the t-byte windows starting
  # in lo..hi occurs. Includes overlapping occurrences, which `:binary.matches`
  # would skip, by restarting the search one byte after each match.
  defp occurrences_of_windows(s, lo, hi, t) when lo <= hi do
    patterns =
      for w <- lo..hi//1, not continuation_byte?(s, w), do: binary_part(s, w, t)

    case patterns do
      [] -> []
      _ -> all_matches(s, :binary.compile_pattern(patterns), 0, [])
    end
  end

  defp occurrences_of_windows(_s, _lo, _hi, _t), do: []

  defp all_matches(s, pattern, from, acc) when from < byte_size(s) do
    case :binary.match(s, pattern, scope: {from, byte_size(s) - from}) do
      {x, _len} -> all_matches(s, pattern, x + 1, [x | acc])
      :nomatch -> :lists.reverse(acc)
    end
  end

  defp all_matches(_s, _pattern, _from, acc), do: :lists.reverse(acc)

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Build [suffix(0), suffix(1), ...] by consing from the back so no reverse is needed.
  # Only offsets on a UTF-8 character boundary become suffixes, matching the NIF's
  # suffix array over Vec<char>; a continuation byte (10xxxxxx) is skipped.
  defp build_suffixes(_s, i, acc) when i < 0, do: acc

  defp build_suffixes(s, i, acc) do
    if continuation_byte?(s, i),
      do: build_suffixes(s, i - 1, acc),
      else: build_suffixes(s, i - 1, [binary_part(s, i, byte_size(s) - i) | acc])
  end

  defp continuation_byte?(s, i) do
    case s do
      <<_::binary-size(^i), 0b10::2, _::bits>> -> true
      _ -> false
    end
  end

  # Walk adjacent pairs of a sorted list of suffixes of an n-byte string; keep
  # the first strict maximum LCP measured in code points, exactly like the NIF's
  # LCP scan over Vec<char>. The byte LCP is an upper bound on the code-point
  # LCP, so we only pay for an exact count when the byte LCP could beat the
  # current best.
  #
  # Also returns the start positions in the same order, dropping duplicates: two
  # suffixes of the same string are identical iff they have the same length.
  defp scan([a, b | rest], n, best_chars, best, positions) do
    if byte_size(a) == byte_size(b) do
      scan([b | rest], n, best_chars, best, positions)
    else
      positions = [n - byte_size(a) | positions]
      bytes = :binary.longest_common_prefix([a, b])

      if bytes > best_chars do
        bytes = trim_to_char_boundary(a, bytes)
        chars = count_codepoints(binary_part(a, 0, bytes), 0)

        if chars > best_chars,
          do: scan([b | rest], n, chars, binary_part(a, 0, bytes), positions),
          else: scan([b | rest], n, best_chars, best, positions)
      else
        scan([b | rest], n, best_chars, best, positions)
      end
    end
  end

  defp scan([a], n, _best_chars, best, positions),
    do: {best, :lists.reverse([n - byte_size(a) | positions])}

  defp scan([], _n, _best_chars, best, positions), do: {best, :lists.reverse(positions)}

  defp count_codepoints(<<_::utf8, rest::binary>>, n), do: count_codepoints(rest, n + 1)
  defp count_codepoints(<<>>, n), do: n

  # Back off (at most 3 bytes) so we never cut inside a multibyte code point.
  defp trim_to_char_boundary(_bin, 0), do: 0

  defp trim_to_char_boundary(bin, len) when len >= byte_size(bin), do: len

  defp trim_to_char_boundary(bin, len) do
    if continuation_byte?(bin, len),
      do: trim_to_char_boundary(bin, len - 1),
      else: len
  end
end
