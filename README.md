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
use({"petertriho/cmp-git", requires = "nvim-lua/plenary.nvim"})
```

## Setup

```lua
require("cmp").setup({
    sources = {
        { name = "cmp_git" },
        -- more sources
    }
})

require("cmp_git").setup()
```

## Config

```lua
require("cmp_git").setup({
    -- defaults
    filetypes = { "gitcommit" },
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    git = {
        commits = {
            sort_by = function(commit) -- nil, "sha", "title", "description", "author_name", "author_email", "commit_timestamp", or custom function
                return string.format("%010d", commit.diff)
            end,
            limit = 100,
            filter_fn = function(trigger_char, commit)
                return string.format("%s %s %s", trigger_char, commit.sha, commit.title)
            end,
        },
    },
    github = {
        issues = {
            filter = "all", -- assigned, created, mentioned, subscribed, all, repos
            limit = 100,
            state = "open", -- open, closed, all
            sort_by = function(issue) -- nil, "number", "title", "body", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_github_date(issue.updatedAt)))
            end,
            filter_fn = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.number, issue.title)
            end,
        },
        mentions = {
            limit = 100,
            sort_by = nil, -- nil, "login", or custom function
            filter_fn = function(trigger_char, mention)
                return string.format("%s %s %s", trigger_char, mention.username)
            end,
        },
        pull_requests = {
            limit = 100,
            state = "open", -- open, closed, merged, all
            sort_by = function(pr) -- nil, "number", "title", "body", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_github_date(pr.updatedAt)))
            end,
            filter_fn = function(trigger_char, pr)
                return string.format("%s %s %s", trigger_char, pr.number, pr.title)
            end,
        },
    },
    gitlab = {
        issues = {
            limit = 100,
            state = "opened", -- opened, closed, all
            sort_by = function(issue) -- nil, "iid", "title", "description", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_gitlab_date(issue.updated_at)))
            end,
            filter_fn = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.iid, issue.title)
            end,
        },
        mentions = {
            limit = 100,
            sort_by = nil, -- nil, "username", "name", or custom function
            filter_fn = function(trigger_char, mention)
                return string.format("%s %s", trigger_char, mention.username)
            end,
        },
        merge_requests = {
            limit = 100,
            state = "opened", -- opened, closed, locked, merged
            sort_by = function(mr) -- nil, "iid", "title", "description", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_gitlab_date(mr.updated_at)))
            end
            filter_fn = function(trigger_char, mr)
                return string.format("%s %s %s", trigger_char, mr.iid, mr.title)
            end,
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

Currently, `trigger_character` has to be a single character. Multiple actions can be used for the same charachter.
All actions are triggered until one returns true. The parameters to the `actions` function are the
different sources (currently `git`, `gitlab` and `github`), the completion callback, the trigger character,
the parameters passed to `complete` from `nvim-cmp`, and the current git info.

All source functions take an optional config table as last argument, with which the configuration set
in `setup` can be overwritten for a specific call.

**NOTE on sorting**

The default sorting, orders by last updated (for PRs, MRs and issues) and latest (for commits).
That the menu is sorted that way, `cmp.config.compare.score,` should be after
`cmp.config.compare.sort_text` in `sorting.comparators`. An example omparators could be:

```lua
require("cmp").setup({
    -- As above
    sorting = {
        comparators = {
            cmp.config.compare.offset,
            cmp.config.compare.exact,
            cmp.config.compare.sort_text,
            cmp.config.compare.score,
            cmp.config.compare.kind,
            cmp.config.compare.length,
            cmp.config.compare.order,
        },
    },
})
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
