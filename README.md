# cmp-git

Git source for [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp) and [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp).

## Features

| Git                | Trigger                                                                  |
| ------------------ | ------------------------------------------------------------------------ |
| Commits            | :                                                                        |
| Trailer keys       | A word at the start of a line in a commit message                        |
| Trailer identities | `Name <email>` after an identity key, such as `Co-authored-by: `         |
| Trailer values     | An earlier value of the key after any other key, such as `Assisted-by: ` |

| GitHub        | Trigger |
| ------------- | ------- |
| Issues        | #       |
| Mentions      | @       |
| Pull Requests | #       |

| GitLab         | Trigger |
| -------------- | ------- |
| Issues         | #       |
| Mentions       | @       |
| Merge Requests | !       |

## Requirements

- Neovim >= 0.12
- git (>= 2.31 to find trailer keys in history)
- curl (>= 7.55)
- [GitHub CLI](https://cli.github.com/) (optional, cmp-git uses curl if it is not available)
- [GitLab CLI](https://gitlab.com/gitlab-org/cli) (optional, cmp-git uses curl if it is not available)

### GitHub private repositories

- `curl`: Generate a [token](https://github.com/settings/tokens) with the `repo` scope. Set the `GITHUB_API_TOKEN`
  environment variable to the token.
- `GitHub CLI`: Run [gh auth login](https://cli.github.com/manual/gh_auth_login).

### GitLab private repositories

- `curl`: Generate a [token](https://gitlab.com/-/profile/personal_access_tokens) with the `api` scope. Set the
  `GITLAB_TOKEN` environment variable to the token.
- `GitLab CLI`: Run [glab auth login](https://glab.readthedocs.io/en/latest/auth/login.html).

## Installation

[vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'petertriho/cmp-git'
```

[packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use("petertriho/cmp-git")
```

[lazy.nvim](https://github.com/folke/lazy.nvim)

With `nvim-cmp`:

```lua
return {
    "petertriho/cmp-git",
    dependencies = { 'hrsh7th/nvim-cmp' },
    opts = {
        -- options go here
    },
    init = function()
        table.insert(require("cmp").get_config().sources, { name = "git" })
    end
}
```

With `blink.cmp`:

```lua
return {
    "petertriho/cmp-git",
}
```

## Setup

### nvim-cmp

```lua
require("cmp").setup({
    sources = {
        { name = "git" },
        -- more sources
    }
})

require("cmp_git").setup()
```

### blink.cmp

If you use `blink.cmp`, configure cmp-git in your `blink.cmp` setup. Do not call `require("cmp_git").setup()` for
`blink.cmp`. That function registers the `nvim-cmp` source.

```lua
require("blink.cmp").setup({
    sources = {
        default = { "git" },
        providers = {
            git = {
                name = "git",
                module = "cmp_git.blink",
                opts = {
                    -- cmp-git options go here
                },
            },
        },
    },
})
```

To use cmp-git only in commit-related filetypes, add it to `sources.per_filetype` for these filetypes, for example
`gitcommit`, `octo`, or `NeogitCommitMessage`. Your normal `blink.cmp` sources then stay in the other filetypes.

## Config

```lua
local format = require("cmp_git.format")
local sort = require("cmp_git.sort")

require("cmp_git").setup({
    -- defaults
    filetypes = { "gitcommit", "octo", "NeogitCommitMessage" },
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    enableRemoteUrlRewrites = false, -- enable git url rewrites, see https://git-scm.com/docs/git-config#Documentation/git-config.txt-urlltbasegtinsteadOf
    ssh_aliases = {}, -- SSH host aliases and their real hosts, such as { ["github-work"] = "github.com" }
    git = {
        commits = {
            limit = 100,
            sort_by = sort.git.commits,
            format = format.git.commits,
            sha_length = 7,
        },
        trailers = {
            filetypes = { "gitcommit", "NeogitCommitMessage" },
            min_line = 3, -- first line where trailers complete, below the subject and its blank line
            keys = {
                builtin = {
                    "Co-authored-by", "Signed-off-by", "Reviewed-by", "Acked-by", "Tested-by",
                    "Reported-by", "Suggested-by", "Helped-by", "Fixes", "Closes", "Refs",
                },
                limit = 100, -- commits scanned for keys
                sort_by = sort.git.trailers.keys,
                format = format.git.trailers.keys,
            },
            identities = {
                -- trailer keys whose values are completed with `Name <email>`
                keys = {
                    "Co-authored-by", "Signed-off-by", "Reviewed-by", "Acked-by", "Tested-by",
                    "Reported-by", "Suggested-by", "Helped-by",
                },
                limit = 1000, -- commits scanned for identities
                sort_by = sort.git.trailers.identities,
                format = format.git.trailers.identities,
            },
            -- earlier values of the current key, for keys that `identities` does not handle
            values = {
                limit = 1000, -- commits scanned for values
                sort_by = sort.git.trailers.values,
                format = format.git.trailers.values,
            },
        },
    },
    github = {
        hosts = {},  -- list of private instances of github
        issues = {
            fields = { "title", "number", "body", "updatedAt", "state" },
            filter = "all", -- all, assigned, created, mentioned
            limit = 100,
            state = "open", -- open, closed, all
            sort_by = sort.github.issues,
            format = format.github.issues,
        },
        mentions = {
            limit = 100,
            sort_by = sort.github.mentions,
            format = format.github.mentions,
        },
        pull_requests = {
            fields = { "title", "number", "body", "updatedAt", "state" },
            limit = 100,
            state = "open", -- open, closed, merged, all
            sort_by = sort.github.pull_requests,
            format = format.github.pull_requests,
        },
    },
    gitlab = {
        hosts = {},  -- list of private instances of gitlab, with the path prefix if any, such as "example.com/gitlab"
        issues = {
            limit = 100,
            state = "opened", -- opened, closed, all
            sort_by = sort.gitlab.issues,
            format = format.gitlab.issues,
        },
        mentions = {
            limit = 100,
            sort_by = sort.gitlab.mentions,
            format = format.gitlab.mentions,
        },
        merge_requests = {
            limit = 100,
            state = "opened", -- opened, closed, locked, merged
            sort_by = sort.gitlab.merge_requests,
            format = format.gitlab.merge_requests,
        },
    },
    trigger_actions = {
        {
            pattern = [[^[[:alnum:]-]\+]],
            actions = { "git_trailer_keys" },
        },
        {
            pattern = [[^[[:alnum:]-]\+:\s*\zs\%([^[:space:]<>:#@!][^<>:#@!]*\%(<[^>]*\)\?\)\?]],
            keyword_pattern = [[^[[:alnum:]-]\+\zs:\S*\|^[[:alnum:]-]\+:\s*\zs\%([^[:space:]<>:#@!][^<>:#@!]*\%(<[^>]*\)\?\)\?]],
            actions = { "git_trailer_identities", "git_trailer_values" },
        },
        {
            trigger_character = ":",
            actions = { "git_commits" },
        },
        {
            trigger_character = "#",
            actions = { "gitlab_issues", "github_issues_and_change_requests" },
        },
        {
            trigger_character = "@",
            actions = { "gitlab_mentions", "github_mentions" },
        },
        {
            trigger_character = "!",
            actions = { "gitlab_change_requests" },
        },
    },
  }
)
```

[docs/configuration.md](docs/configuration.md) describes these topics:

- [Trigger actions](docs/configuration.md#trigger-actions)
- [Trailer completion](docs/configuration.md#trailer-completion)
- [Format and sort items](docs/configuration.md#format-and-sort-items)
- [Filetypes](docs/configuration.md#filetypes)
- [Remotes and SSH aliases](docs/configuration.md#remotes-and-ssh-aliases)
- [GitHub CLI, GitLab CLI, and curl](docs/configuration.md#github-cli-gitlab-cli-and-curl)
- [Hosted GitHub and GitLab instances](docs/configuration.md#hosted-github-and-gitlab-instances)
- [Troubleshooting](docs/configuration.md#troubleshooting)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup, the tests, and the CI checks.

## Acknowledgements

Special thanks to [tjdevries](https://github.com/tjdevries) for their informative video and starting code.

- [TakeTuesday E01: nvim-cmp](https://www.youtube.com/watch?v=_DnmphIwnjo)
- [tjdevries/config_manager](https://github.com/tjdevries/config_manager)

## Alternatives

- [neoclide/coc-git](https://github.com/neoclide/coc-git)

## License

[MIT](https://choosealicense.com/licenses/mit/)
