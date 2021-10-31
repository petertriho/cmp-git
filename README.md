# cmp-git

# 🚧 WORK IN PROGRESS 🚧

This is a work in prgress and breaking changes to the setup/config could occur
in the future. Sorry for any inconveniences.

Git source for [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)

## Features

| Git     | Trigger |
| ------- | ------- |
| Commits | :       |

| GitHub                 | Trigger |
| ---------------------- | ------- |
| Issues                 | #       |
| Mentions (`curl` only) | @       |
| Pull Requests          | #       |

| GitLab         | Trigger |
| -------------- | ------- |
| Issues         | #       |
| Mentions       | @       |
| Merge Requests | !       |

## Requirements

- Neovim >= 0.5.1
- git
- curl
- [GitHub CLI](https://cli.github.com/) (optional, will use curl instead if not avaliable)
- [GitLab CLI (unofficial)](https://github.com/profclems/glab) (optional, will use curl instead if not avaliable)

### GitHub Private Repositories

- `curl`: Generate [token](https://github.com/settings/tokens)
  with `repo` scope. Set `GITHUB_API_TOKEN` environment variable.
- `GitHub CLI`: Run [gh auth login](https://cli.github.com/manual/gh_auth_login)

### GitLab Private Repositories

- `curl` Generate [token](https://gitlab.com/-/profile/personal_access_tokens)
  with `api` scope. Set `GITLAB_TOKEN` environment variable.
- `GitLab CLI`: Run [glab auth login](https://glab.readthedocs.io/en/latest/auth/login.html)

## Installation

[vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'petertriho/cmp-git'
```

[packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use("petertriho/cmp-git", requires = "nvim-lua/plenary.nvim")
```

## Setup

```lua
require("cmp").setup({
    sources = {
        { name = "cmp_git" },
        -- more sources
    }
})

require("cmp_git").setup({
    -- defaults
    filetypes = { "gitcommit" },
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    git = {
        commits = {
            limit = 100,
        },
    },
    github = {
        issues = {
            filter = "all", -- assigned, created, mentioned, subscribed, all, repos
            limit = 100,
            state = "open", -- open, closed, all
        },
        mentions = {
            limit = 100,
        },
        pull_requests = {
            limit = 100,
            state = "open", -- open, closed, merged, all
        },
    },
    gitlab = {
        issues = {
            limit = 100,
            state = "opened", -- opened, closed, all
        },
        mentions = {
            limit = 100,
        },
        merge_requests = {
            limit = 100,
            state = "opened", -- opened, closed, locked, merged
        },
    },
})
```

## Acknowledgements

Special thanks to [tjdevries](https://github.com/tjdevries) for their informative video and starting code.

- [TakeTuesday E01: nvim-cmp](https://www.youtube.com/watch?v=_DnmphIwnjo)
- [tjdevries/config_manager](https://github.com/tjdevries/config_manager)

## Alternatives

- [neoclide/coc-git](https://github.com/neoclide/coc-git)

## License

[MIT](https://choosealicense.com/licenses/mit/)
