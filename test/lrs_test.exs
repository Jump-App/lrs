defmodule LRSTest do
  use ExUnit.Case, async: true

  test "finds longest repeating substring" do
    assert "GEEKS" = LRS.longest_repeating_substring("GEEKSFORGEEKS$")
    assert "" = LRS.longest_repeating_substring("ABCDEFG$")
    assert "ABABA" = LRS.longest_repeating_substring("ABABABA$")
    assert "ATCGA" = LRS.longest_repeating_substring("ATCGATCGA$")
    assert "ana" = LRS.longest_repeating_substring("banana$")
    assert "ab" = LRS.longest_repeating_substring("abcpqrabpqpq$")
    assert "ab" = LRS.longest_repeating_substring("pqrpqpqabab$")
  end

  test "recursively removes" do
    text =
      "This is a long text with some repeating text that is long is a long text and it should return"

    assert LRS.recursively_remove_repeating_substring(text, 100) == text
    assert LRS.recursively_remove_repeating_substring(text, 30) == text

    assert LRS.recursively_remove_repeating_substring(text, 10) ==
             "This with some repeating text that is long is a long text and it should return"

    assert LRS.recursively_remove_repeating_substring("") == ""
  end
end
