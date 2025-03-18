To cut a release for the GitHub-hosted artifact:

1. Update the version number in mix.exs to your target version. This should
   match the target release tag number.
2. Push your changes to `main`
3. Tag the release [using the GitHub UI](https://github.com/Jump-App/lrs/releases)
4. Wait for the NIF build to complete (watch the GitHub Actions workflows complete within [the "all commits" view](https://github.com/Jump-App/lrs/commits/main/))
5. Locally, run `mix rustler_precompiled.download LRS --all --ignore-unavailable --no-config`
6. Confirm `checksum-Elixir.LRS.exs` has been modified
7. Commit that file to Git and create a _second_ PR for it ([example](https://github.com/Jump-App/lrs/pull/7))
8. Run `mix deps.update lrs` in the client application—it should grab the latest commit from `main`, rather than the tagged version you previously created
