# GitHub Release Script

This project provides a **bash script** (`github-release.sh`) to automate creating and updating GitHub repositories with releases.

## Features

- Initialize a Git repository if it doesn’t exist
- Create the remote GitHub repository automatically (via `gh` CLI or REST API with `$GITHUB_TOKEN`)
- Handle first push and subsequent updates
- Create annotated tags and GitHub Releases
- Optionally zip the project and attach it to the release

## Requirements

- `git`
- Either:
  - [GitHub CLI](https://cli.github.com/) (`gh`) authenticated, or
  - `GITHUB_TOKEN` environment variable with `repo` scope
- `zip` (if you want to attach an archive)

## Usage

```bash
./github-release.sh -d <code_dir> -r <owner/repo> [options]
```

### Options

- `-d, --dir DIR` : Path to the code directory (required)
- `-r, --repo OWNER/NAME` : Full repo name (e.g., `michaelspatrick/my-repo`)
- `-o, --owner OWNER` and `-n, --name NAME` : Alternative to `--repo`
- `-b, --branch BRANCH` : Default branch (default: `main`)
- `--public` : Make repo public (default: private)
- `--zip` : Zip project and attach to release
- `-v, --version TAG` : Release tag (default: `vYYYYMMDD-HHMMSS`)
- `-m, --message MSG` : Commit message / release notes

## Example

```bash
# First release
./github-release.sh -d /opt/my-project -r michaelspatrick/my-project -m "Initial release" --public --zip

# Update and push changes
./github-release.sh -d /opt/my-project -r michaelspatrick/my-project -m "Bug fixes" -v v1.0.1
```

## License

MIT
