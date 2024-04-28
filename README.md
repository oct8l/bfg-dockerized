# BFG Repo-Cleaner

[BFG](https://rtyley.github.io/bfg-repo-cleaner/), Dockerized!

## Usage

You could run BFG in a container by executing the following `docker` command.

```bash
docker run -it --rm \
  --volume "$PWD:/home/bfg/workspace" \
  ghcr.io/oct8l/bfg-dockerized:latest \
  --no-blob-protection --delete-files credential.json
```

This will mount the current directory to the container and then run BFG with the specified arguments. In the case above, the `--delete-files` argument is used to specify the files to be deleted and the `--no-blob-protection` argument is used to disable blob protection, which is a feature that can be used to protect certain files from being deleted by BFG.

You could even create wrapper functions for your `docker run` commands ([example](https://github.com/jessfraz/dotfiles/blob/master/.dockerfunc)):

```bash
bfg() {
docker run -it --rm \
  --volume "$PWD:/home/bfg/workspace" \
  ghcr.io/oct8l/bfg-dockerized:latest \
  $@
}
```

Of course, you can modify the `bfg` function to fit your needs. For example, you can add the `--no-blob-protection` flag to the `bfg` function to disable blob protection, as well as specify that you want to delete a file:

```bash
bfg() {
docker run -it --rm \
  --volume "$PWD:/home/bfg/workspace" \
  ghcr.io/oct8l/bfg-dockerized:latest \
  --no-blob-protection --delete-files $@
}
```
