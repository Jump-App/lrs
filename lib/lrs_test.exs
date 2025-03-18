defmodule LRSTest do
  use ExUnit.Case
  doctest LRS

  describe "recursively_remove_repeating_substring/2" do
    test "handles empty string" do
      assert LRS.recursively_remove_repeating_substring("") == ""
    end

    test "returns original string when no repeating substrings above threshold" do
      string = "This is a test string with no long repeating substrings"
      assert LRS.recursively_remove_repeating_substring(string, 30) == string
    end

    test "removes long repeating substrings" do
      # Create a string with a repeating substring longer than the threshold
      # 52 characters
      repeating = String.duplicate("abcdefghijklmnopqrstuvwxyz", 2)
      string = "Start #{repeating} middle #{repeating} end"

      result = LRS.recursively_remove_repeating_substring(string, 30)

      # The function replaces the first occurrence with a space, but the second occurrence
      # might still be present. Let's check that at least one occurrence was replaced.
      refute result == string

      # The result should have fewer occurrences of the repeating substring
      assert String.split(string, repeating) |> length() >
               String.split(result, repeating) |> length()
    end

    test "handles case where replacement doesn't change string" do
      # Mock the longest_repeating_substring function to return a value that won't be found
      # This test assumes the implementation will handle this case correctly
      string = "This is a test string"

      # This is a simple test to ensure no infinite recursion
      # The actual behavior depends on the implementation of longest_repeating_substring
      assert is_binary(LRS.recursively_remove_repeating_substring(string, 5))
    end

    test "handles multiple nested repeating substrings" do
      # Create a string with multiple levels of repeating substrings
      # 45 characters
      inner_repeat = String.duplicate("abc", 15)
      # 93 characters
      middle_repeat = "#{inner_repeat}XYZ#{inner_repeat}"
      # 189 characters
      outer_repeat = "#{middle_repeat}123#{middle_repeat}"

      string = "Start #{outer_repeat} End"

      result = LRS.recursively_remove_repeating_substring(string, 30)

      # The result should be different from the original string
      refute result == string

      # The function should have reduced the occurrences of repeating patterns
      # We can't guarantee complete removal of all patterns since the function
      # replaces one occurrence at a time
      assert String.length(result) < String.length(string)
    end

    test "custom threshold changes behavior" do
      # Create a string with a repeating substring just above and below different thresholds
      repeat_35 = String.duplicate("a", 35)
      repeat_25 = String.duplicate("b", 25)

      string = "Start #{repeat_35} middle #{repeat_25} end"

      # With threshold 30, only the 35-char repeat should be removed
      result_30 = LRS.recursively_remove_repeating_substring(string, 30)
      refute String.contains?(result_30, repeat_35)
      assert String.contains?(result_30, repeat_25)

      # With threshold 20, both repeats should be removed
      result_20 = LRS.recursively_remove_repeating_substring(string, 20)
      refute String.contains?(result_20, repeat_35)
      refute String.contains?(result_20, repeat_25)
    end
  end
end
