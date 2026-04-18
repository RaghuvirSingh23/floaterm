# Releasing Floaterm

## What ships

GitHub releases now build the native macOS Swift app and attach:

- a `.zip` containing `floaterm.app`
- a `.dmg` with `floaterm.app` and an `Applications` shortcut
- a SHA-256 checksum file for both artifacts

## How to cut a release

1. Tag the commit you want to ship.
2. Push the tag to GitHub.

Example:

```bash
git tag v0.1.0
git push origin v0.1.0
```

That triggers `.github/workflows/release.yml`, which builds the app on macOS and publishes a GitHub release for that tag.

## Manual release runs

You can also run the release workflow manually from GitHub Actions and pass a `release_tag` such as `v0.1.1`.

If the tag does not exist yet, the workflow creates the release from the selected commit.

## Current status

The pipeline currently produces unsigned artifacts. That is fine for GitHub-hosted downloads and internal testing, but Gatekeeper warnings will still apply.

The next distribution step after this is:

1. Apple Developer signing
2. notarization
3. optional stapling in the release workflow
