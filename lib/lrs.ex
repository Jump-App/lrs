defmodule LRS do
  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :lrs,
    crate: :lrs,
    base_url: "https://github.com/Jump/lrs/releases/download/v#{version}",
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
      string
      |> String.replace(longest, " ", global: false)
      |> recursively_remove_repeating_substring(above_size)
    else
      string
    end
  end
end
