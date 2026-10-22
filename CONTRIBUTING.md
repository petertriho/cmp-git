# Contributing

## Requirements

Use one of these setups:

- Nix with flakes, and direnv. The flake gives the same tool versions that CI uses.
- These tools on your `PATH`: Neovim >= 0.12, git, make, [StyLua](https://github.com/JohnnyMorganz/StyLua),
  [Selene](https://github.com/Kampfkarren/selene), and
  [lua-language-server](https://github.com/LuaLS/lua-language-server).

CI is authoritative. Other versions of these tools can give different results.

The first `make test` or `make typecheck` clones mini.nvim, so this first run needs network access.

## Development shells

To load the default shell when you enter the repository:

1. Install Nix and enable flakes.
2. Install direnv and hook it into your shell.
3. In the repository, run `direnv allow`.

The flake has three shells. Each shell also has StyLua, Selene, lua-language-server, make, and git.

| Shell         | Neovim                                                   | Command                     |
| ------------- | -------------------------------------------------------- | --------------------------- |
| `default`     | The stable release in the locked nixpkgs                 | `nix develop`               |
| `nvim-0_12_0` | 0.12.0, the minimum supported version                    | `nix develop .#nvim-0_12_0` |
| `nightly`     | The nightly build in the locked `neovim-nightly-overlay` | `nix develop .#nightly`     |

The nightly builds are in the nix-community binary cache. Without this cache, Nix builds Neovim from source. To use
the cache, add these lines to your Nix config:

```
extra-substituters = https://nix-community.cachix.org
extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
```

## Make targets

| Target                         | Action                                                                                              |
| ------------------------------ | --------------------------------------------------------------------------------------------------- |
| `make test`                    | Runs all tests.                                                                                     |
| `make test-file FILE=<path>`   | Runs one test file.                                                                                 |
| `make format`                  | Formats `lua/`, `tests/`, and `benchmarks/` with StyLua.                                            |
| `make format-check`            | Checks the formatting.                                                                              |
| `make lint`                    | Lints `lua/`, `tests/`, and `benchmarks/` with Selene. Warnings fail the target.                    |
| `make typecheck`               | Checks the types with lua-language-server. Warnings fail the target.                                |
| `make ci`                      | Runs `format-check`, `lint`, `typecheck`, and `test`.                                               |
| `make test-deps`               | Clones mini.nvim at `MINI_VERSION` into `deps/`. `test`, `test-file`, and `typecheck` run it first. |
| `make bench`                   | Runs the benchmarks. Options go in `BENCH_ARGS`.                                                    |
| `make bench-compare REF=<rev>` | Compares the benchmarks of `<rev>` (default `main`) with the working tree.                          |

To use a different tool, set its variable: `NVIM`, `STYLUA`, `SELENE`, or `LUA_LANGUAGE_SERVER`. For example:

```sh
make test NVIM=~/.local/bin/nvim
```

`make typecheck` gets `$VIMRUNTIME` from `$(NVIM)`, so lua-language-server checks the code against the Neovim API of
that version.

## Tests

The tests use [mini.test](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-test.md). The files in
`tests/` mirror the modules in `lua/cmp_git/`. mini.test collects the files that match `tests/**/test_*.lua`.

- `tests/minimal_init.lua` adds the repository and mini.nvim to `runtimepath`.
- `tests/helpers.lua` has the expectations, the fakes, and the hooks for each case.

Start each test file with `local T = helpers.new_set()`. The hooks of this set isolate each case:

- They capture `vim.notify`, so log messages do not print. To read the messages, call `helpers.flush()`, and then
  read `helpers.notifications`.
- They unset `GITHUB_API_TOKEN` and `GITLAB_TOKEN`.
- They isolate git from your user config and your system config.
- They restore the cwd, the buffers, and the values that `helpers.stub` replaced.
- They delete the directories from `helpers.tempdir` and `helpers.git_repo`.

Do not use the network in tests. Use fake runners and fake adapters in place of `gh`, `glab`, and `curl`.

To run one test file:

```sh
make test-file FILE=tests/test_core.lua
```

To run the tests on Neovim 0.12.0 and on nightly:

```sh
nix develop .#nvim-0_12_0 -c make test
nix develop .#nightly -c make test
```

The `Neovim nightly` job tests the newest nightly that is in the cache, not the locked nightly. To do the same test on
your computer, run these commands. `scripts/nightly-cache.sh latest` needs an authenticated `gh`, and it checks the last
10 overlay commits. To check more commits, give a count, for example `latest 20`.

```sh
rev=$(scripts/nightly-cache.sh latest)
nix develop .#nightly --no-write-lock-file \
  --override-input neovim-nightly-overlay "github:nix-community/neovim-nightly-overlay/$rev" -c make test
```

## Benchmarks

The benchmarks in `benchmarks/` measure the two costs that users feel: the work that runs while they type, and the time
until the completion items show. Nothing in them uses the network.

| Group        | Cases                            | Measures                                                                              |
| ------------ | -------------------------------- | ------------------------------------------------------------------------------------- |
| `keystroke/` | `benchmarks/cases/keystroke.lua` | The checks that nvim-cmp and blink.cmp make on each keystroke, and declined requests. |
| `request/`   | `benchmarks/cases/request.lua`   | Routing, parsing, and item formatting for one request. Also the startup cost.         |
| `e2e/`       | `benchmarks/cases/e2e.lua`       | One request from start to the final callback, in a git repository with 1000 commits.  |

The `e2e/` cases run the real git commands. A fake `gh` in a temporary directory answers the GitHub requests at once,
so the times include the process starts, but not the network or the run time of the real `gh`. `cold` cases use a new
source for each request. `warm` cases repeat a request that the cache can answer.

Each line of the report has these values:

| Value      | Meaning                                                                                                  |
| ---------- | -------------------------------------------------------------------------------------------------------- |
| `median`   | The median time of one operation.                                                                        |
| `alloc`    | The Lua memory that one operation allocates. It does not change between runs, so it shows small changes. |
| `main`     | `e2e/` only. The main-thread time of one request. Neovim cannot handle a keystroke during this time.     |
| `block`    | `e2e/` only. The longest uninterrupted main-thread slice of one request.                                 |
| `spawns`   | The processes that one operation starts.                                                                 |
| `blocking` | The synchronous process calls (`vim.fn.system`) of one operation. These stop Neovim until they finish.   |

To run the benchmarks:

```sh
make bench
make bench BENCH_ARGS="--filter keystroke"
```

To compare your changes with `main`:

```sh
make bench-compare
```

`scripts/bench-compare.sh` runs the cases of the working tree on the `lua/` code of both revisions, two runs each,
and keeps the best value of each side. It reports a regression when a time grows by more than 25%, an allocation
grows by more than 10%, or a process count grows. Very small changes do not count. The options of
`benchmarks/compare.lua` change the limits.

To add a case, add it to the file of its group. A case that starts a process must be an async case that calls `done`.
Use the fixtures in `benchmarks/fixtures.lua` so that the case does not use the network.

## CI

The workflow in `.github/workflows/ci.yml` runs on pushes to `main`, on pull requests, and on manual dispatch. It
has these jobs:

| Job              | Steps                                                                                                     | Blocks |
| ---------------- | --------------------------------------------------------------------------------------------------------- | ------ |
| `Quality`        | `make format-check`, `make lint`, and `make typecheck` in the default shell                               | Yes    |
| `Neovim stable`  | `make test` in the default shell                                                                          | Yes    |
| `Neovim 0.12.0`  | `make test` in the `nvim-0_12_0` shell                                                                    | Yes    |
| `Nightly cache`  | `scripts/nightly-cache.sh check` (the locked nightly Neovim is in the cache for each system)              | Yes    |
| `Neovim nightly` | `make test` with the newest `neovim-nightly-overlay` commit that is in the cache, not the locked revision | No     |

A weekly schedule (Monday 06:00 UTC) runs only the nightly job. GitHub disables scheduled workflows after 60 days
without repository activity. To enable the schedule again, use the Actions tab of the repository.

## Dependency updates

Each month, Dependabot opens up to two grouped pull requests:

- `github-actions` updates the action SHAs in the workflow.
- `nix` updates the inputs in `flake.lock`.

A nixpkgs update can change the versions of StyLua, Selene, lua-language-server, and stable Neovim. If the `Quality`
job then fails, do these steps on the Dependabot branch:

1. Run `make format`.
2. Fix the lint and type warnings, if there are any.
3. Push the changes to the branch.

A `nix` update can lock a `neovim-nightly-overlay` commit whose Neovim is not in the cache yet. Then
`nix develop .#nightly` builds Neovim from source, and the `Nightly cache` job fails. The overlay updates each day at
00:00 UTC, and its CI pushes the build to the cache later. If the job fails, do these steps. Step 2 removes the
changes that you pushed to the branch.

1. Later the same day, run the job again.
2. If the job still fails, comment `@dependabot recreate` on the pull request. Dependabot then locks the newest
   overlay commit.
3. If you pushed changes to the branch before step 2, push them again.

To check the locked nightly Neovim on your computer, run `scripts/nightly-cache.sh check`.

Dependabot does not change the Neovim 0.12.0 pin in `flake.nix`.

### Update mini.nvim

Dependabot does not update mini.nvim. To update it:

1. Find the latest release tag of [mini.nvim](https://github.com/nvim-mini/mini.nvim/releases).
2. Set `MINI_VERSION` in the `Makefile` to the tag.
3. Run `make test`. `make test-deps` checks out the new tag in `deps/mini.nvim`.
4. Commit the `Makefile`.
