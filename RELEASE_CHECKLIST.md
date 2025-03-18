To cut a release for the GitHub-hosted artifact:

1. Push your changes to `main`
2. Tag the release [using the GitHub UI](https://github.com/Jump-App/lrs/releases)
3. Wait for the NIF build to complete (watch the GitHub Actions workflows complete within [the "all commits" view](https://github.com/Jump-App/lrs/commits/main/))
4. Locally, run `mix rustler_precompiled.download LRS --all --ignore-unavailable --no-config`
5. Confirm `checksum-Elixir.LRS.exs` has been modified
6. Commit that file to Git and create a _second_ PR for it ([example](https://github.com/Jump-App/lrs/pull/7))
7. Run `mix deps.update lrs` in the client application—it should grab the latest commit from `main`, rather than the tagged version you previously created 
