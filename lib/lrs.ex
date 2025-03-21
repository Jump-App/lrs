defmodule LRS do
  @moduledoc """
  A Rust precompiled NIF for finding the longest recurring substring in a string.
  """

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :lrs,
    crate: :lrs,
    base_url: "https://github.com/Jump-App/lrs/releases/download/v#{version}",
    version: version,
    force_build: System.get_env("LRS_FORCE_BUILD") == "true"

  # Define the function signature that matches the Rust NIF
  @spec longest_repeating_substring(String.t()) :: {:ok, String.t()}
  def longest_repeating_substring(""), do: ""
  def longest_repeating_substring(_string), do: :erlang.nif_error(:nif_not_loaded)

  def recursively_remove_repeating_substring(string, above_size \\ 30)
  def recursively_remove_repeating_substring("", _), do: ""

  def recursively_remove_repeating_substring(string, above_size) do
    longest = longest_repeating_substring(string)

    if String.length(longest) > above_size do
      new_string = String.replace(string, longest, " ", global: false)

      # Check if the string actually changed after replacement
      if new_string != string do
        recursively_remove_repeating_substring(new_string, above_size)
      else
        string
      end
    else
      string
    end
  end
end
