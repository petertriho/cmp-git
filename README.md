# cmp-git

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
- [GitLab CLI](https://gitlab.com/gitlab-org/cli) (optional, will use curl instead if not avaliable)

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
use({"petertriho/cmp-git", requires = "nvim-lua/plenary.nvim"})
```

## Setup

```lua
require("cmp").setup({
    sources = {
        { name = "git" },
        -- more sources
    }
})

require("cmp_git").setup()
```

## Config

```lua
local format = require("cmp_git.format")
local sort = require("cmp_git.sort")

require("cmp_git").setup({
    -- defaults
    filetypes = { "gitcommit", "octo" },
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    enableRemoteUrlRewrites = false, -- enable git url rewrites, see https://git-scm.com/docs/git-config#Documentation/git-config.txt-urlltbasegtinsteadOf
    git = {
        commits = {
            limit = 100,
            sort_by = sort.git.commits,
            format = format.git.commits,
        },
    },
    github = {
        hosts = {},  -- list of private instances of github
        issues = {
            fields = { "title", "number", "body", "updatedAt", "state" },
            filter = "all", -- assigned, created, mentioned, subscribed, all, repos
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
        hosts = {},  -- list of private instances of gitlab
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
            debug_name = "git_commits",
            trigger_character = ":",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.git:get_commits(callback, params, trigger_char)
            end,
        },
        {
            debug_name = "gitlab_issues",
            trigger_character = "#",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.gitlab:get_issues(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "gitlab_mentions",
            trigger_character = "@",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.gitlab:get_mentions(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "gitlab_mrs",
            trigger_character = "!",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.gitlab:get_merge_requests(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "github_issues_and_pr",
            trigger_character = "#",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.github:get_issues_and_prs(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "github_mentions",
            trigger_character = "@",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.github:get_mentions(callback, git_info, trigger_char)
            end,
        },
    },
  }
)
```

---

**NOTE**

If you want specific behaviour for a trigger or new behaviour for a trigger, you need to add
an entry in the `trigger_actions` table of the config. The two necessary fields are the `trigger_character`
and the `action`.

Currently, `trigger_character` has to be a single character. Multiple actions can be used for the same character.
All actions are triggered until one returns true. The parameters to the `actions` function are the
different sources (currently `git`, `gitlab` and `github`), the completion callback, the trigger character,
the parameters passed to `complete` from `nvim-cmp`, and the current git info.

All source functions take an optional config table as last argument, with which the configuration set
in `setup` can be overwritten for a specific call.

**NOTE on sorting**

The default sorting order is last updated (for PRs, MRs and issues) and latest (for commits).
To make `nvim-cmp` sort in this order, move `cmp.config.compare.sort_text` closer to the top of (lower index) in `sorting.comparators`. E.g.

```lua
require("cmp").setup({
    -- As above
    sorting = {
        comparators = {
            cmp.config.compare.offset,
            cmp.config.compare.exact,
            cmp.config.compare.sort_text,
            cmp.config.compare.score,
            cmp.config.compare.recently_used,
            cmp.config.compare.kind,
            cmp.config.compare.length,
            cmp.config.compare.order,
        },
    },
})
```

### Working with hosted instances of GitHub or GitLab

You can add hosted instances of Github Enterprise or GitLab to the corresponding `hosts` list as such:
```lua
require("cmp_git").setup({
    github = {
        hosts = { "github.mycompany.com", },
    },
    gitlab = {
        hosts = { "gitlab.mycompany.com", }
    }
}
```

---

## Acknowledgements

Special thanks to [tjdevries](https://github.com/tjdevries) for their informative video and starting code.

- [TakeTuesday E01: nvim-cmp](https://www.youtube.com/watch?v=_DnmphIwnjo)
- [tjdevries/config_manager](https://github.com/tjdevries/config_manager)

## Alternatives

- [neoclide/coc-git](https://github.com/neoclide/coc-git)

## License

[MIT](https://choosealicense.com/licenses/mit/)
