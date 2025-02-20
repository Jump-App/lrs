To cut a release for the GitHub-hosted artifact:

1. Push your changes to `main`
2. Tag the release [using the GitHub UI](https://github.com/Jump-App/lrs/releases)
3. Wait for the NIF build to complete
4. Locally, run `mix rustler_precompiled.download LRS --all --ignore-unavailable --no-config`
5. Confirm `checksum-Elixir.LRS.exs` has been created
6. Commit that file to Git
7. Run `mix deps.update lrs` in the client application
