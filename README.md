# Voicenotes

Record and play voice notes on a Garmin watch. Keep them on the watch, upload them to your own server, or sync them to Android from a fēnix 8.

- [User guide](docs/index.qmd) for installing Voicenotes, recording on your watch, and exporting notes.
- [Developer docs](docs/developer/index.qmd) for building the apps and running tests.
- [Published documentation](https://mnboos.github.io/garmin-voicenotes/).

## Build and preview

Run `just garmin-build-app` to build for the fēnix 8 47 mm. See [Build the watch app](docs/developer/setup.qmd) for other models.

Run `just docs-preview` to preview the documentation or `quarto render docs` to build `docs/_site`.

To serve the site at `http://localhost:8080` with Docker, run:

```sh
docker build -t voicenotes-docs docs
docker run --rm -p 127.0.0.1:8080:8080 voicenotes-docs
```

The Docker build uses Linux amd64 for Quarto and a native runtime image.

## Publish the docs

The Docs workflow builds the site on pull requests and pushes to `main`. Publishing a stable GitHub Release deploys the docs from its tag.

To replace the live site manually, open **Actions → Docs → Run workflow**, select the ref to publish, and run the workflow.

For initial setup, select **GitHub Actions** under **Settings → Pages → Build and deployment → Source**. Under **Settings → Environments → github-pages**, allow branches and tags under **Deployment branches and tags** so release tags and manually selected refs can deploy.

## License

[GNU Affero General Public License, version 3 only](LICENSE) (`AGPL-3.0-only`). Third-party materials retain their licenses.
