# cmp-git

Git source for [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp) and [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp).

## Features

| Git                | Trigger                                                                  |
| ------------------ | ------------------------------------------------------------------------ |
| Commits            | :                                                                        |
| Trailer keys       | A word at the start of a line in a commit message                        |
| Trailer identities | `Name <email>` after an identity key, such as `Co-authored-by: `         |
| Trailer values     | An earlier value of the key after any other key, such as `Assisted-by: ` |

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
- git (>= 2.31 to find trailer keys in history)
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

`blink.cmp` support is optional and configured from your `blink.cmp` setup. Do not call `require("cmp_git").setup()` for blink; that function registers the `nvim-cmp` source.

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

To enable `cmp-git` only for commit-related filetypes while keeping your normal blink sources elsewhere, add it through blink's `sources.per_filetype` configuration for filetypes such as `gitcommit`, `octo`, or `NeogitCommitMessage`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup, the tests, and the CI checks.

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
            pattern = [[^[[:alnum:]-]\+]],
            actions = { "git_trailer_keys" },
        },
        {
            pattern = [[\%(^[[:alnum:]-]\+:\s*\)\@<=\%([^[:space:]<>:#@!][^<>:#@!]*\%(<[^>]*\)\?\)\?]],
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

Capability-level `format.filterText` is the preferred way to customize completion filtering. Provider-level
`filter_fn` is supported as a compatibility alias and is applied to every capability for that provider,
except `git.filter_fn`, which applies only to `git.commits`.

---

**NOTE**

If you want specific behaviour for a trigger, add an entry in the `trigger_actions` table of the config.
The preferred fields are `trigger_character` and `actions`. `trigger_character` has to be a single
character, and `actions` is an ordered list of named behaviours. Multiple actions can be used for the same
character; they run in order until one handles the request.

An entry can use `pattern` instead of `trigger_character`. `pattern` is a vim regex in the default `magic`
mode. It applies when it matches the text before the cursor, up to the cursor. The match start is where the
completed text starts. The patterns are also added to the `nvim-cmp` keyword pattern. Entries run in
config order, and the first action that handles the request wins. This is why the trailer entries come
before the `:` entry: `Co-authored-by:` completes identities, not commits.

Built-in actions are `git_commits`, `git_trailer_keys`, `git_trailer_identities`, `git_trailer_values`,
`gitlab_issues`, `gitlab_mentions`, `gitlab_change_requests`, `github_issues`, `github_change_requests`,
`github_issues_and_change_requests`, and `github_mentions`. The `git_trailer_*` actions need a `pattern`
entry.
Compatibility aliases are also available: `gitlab_mrs` routes to `gitlab_change_requests`, and
`github_issues_and_prs` routes to `github_issues_and_change_requests`.

Legacy callback-style trigger actions are still supported for compatibility. These entries use
`trigger_character` and `action`, where `action` receives the different sources (currently `git`, `gitlab`
and `github`), the trigger character, the completion callback, the parameters passed to `complete` from
`nvim-cmp`, and the current git info. New configuration should prefer named `actions` instead.

All source functions take an optional config table as last argument, with which the configuration set
in `setup` can be overwritten for a specific call.

**NOTE on trailers**

| You type             | Completion                                         | From                                           |
| -------------------- | -------------------------------------------------- | ---------------------------------------------- |
| `Co`                 | `Co-authored-by: `                                 | A trailer key                                  |
| `Co-authored-by: Gr` | `Co-authored-by: Grace Hopper <grace@example.com>` | A commit author or identity trailer in history |
| `Signed-off-by:`     | `Signed-off-by: Ada Lovelace <ada@example.com>`    | Your git identity                              |
| `Assisted-by: Cl`    | `Assisted-by: Claude Code`                         | An earlier `Assisted-by` value                 |

Trailer completion works only in the `git.trailers.filetypes` buffers, from line `git.trailers.min_line`
(default 3), and on a line after a blank line or after another `Key: value` line. Line 1 counts as after a
blank line. Keys come from `git.trailers.keys.builtin` and from the last
`git.trailers.keys.limit` commits.

The value of a `git.trailers.identities.keys` trailer completes `Name <email>` from the authors and those
trailers of the last `git.trailers.identities.limit` commits, and from your git identity. The value of any
other trailer completes the values that the same key had in the last `git.trailers.values.limit` commits.
`Key:` with no space after the colon still completes commits for other keys, so `Fixes:` works as before.
Value completion stops when the typed value contains `:`, `#`, `@`, or `!` outside `<...>`, so that these
triggers keep working (for example, `Fixes: #12` completes issues).

To disable trailer completion, set `trigger_actions` without the two `pattern` entries. If you already set
your own `trigger_actions`, add the two `pattern` entries from the defaults above to get trailer completion.

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
