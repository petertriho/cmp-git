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

- Neovim >= 0.12
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
Plug 'petertriho/cmp-git'
```

[packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use("petertriho/cmp-git")
```

[lazy.nvim](https://github.com/folke/lazy.nvim)

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

## Development

Run the tests with:

```sh
nvim --headless -u NONE -l tests/run.lua
```

## Config

```lua
local format = require("cmp_git.format")
local sort = require("cmp_git.sort")

require("cmp_git").setup({
    -- defaults
    filetypes = { "gitcommit", "octo", "NeogitCommitMessage" },
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    enableRemoteUrlRewrites = false, -- enable git url rewrites, see https://git-scm.com/docs/git-config#Documentation/git-config.txt-urlltbasegtinsteadOf
    git = {
        commits = {
            limit = 100,
            sort_by = sort.git.commits,
            format = format.git.commits,
            sha_length = 7,
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

Capability-level `format.filterText` is the preferred way to customize completion filtering. Provider-level
`filter_fn` is supported as a compatibility alias and is applied to every capability for that provider.

---

**NOTE**

If you want specific behaviour for a trigger, add an entry in the `trigger_actions` table of the config.
The preferred fields are `trigger_character` and `actions`. `trigger_character` has to be a single
character, and `actions` is an ordered list of named behaviours. Multiple actions can be used for the same
character; they run in order until one handles the request.

Built-in actions are `git_commits`, `gitlab_issues`, `gitlab_mentions`, `gitlab_change_requests`,
`github_issues`, `github_change_requests`, `github_issues_and_change_requests`, and `github_mentions`.
Compatibility aliases are also available: `gitlab_mrs` routes to `gitlab_change_requests`, and
`github_issues_and_prs` routes to `github_issues_and_change_requests`.

Legacy callback-style trigger actions are still supported for compatibility. These entries use
`trigger_character` and `action`, where `action` receives the different sources (currently `git`, `gitlab`
and `github`), the trigger character, the completion callback, the parameters passed to `complete` from
`nvim-cmp`, and the current git info. New configuration should prefer named `actions` instead.

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
