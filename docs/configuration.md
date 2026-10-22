# Configuration

The [README](../README.md#config) shows the default configuration. This page describes the options that need more
explanation.

## Trigger actions

To change the behavior of a trigger, add an entry to `trigger_actions`. The preferred fields of an entry are
`trigger_character` and `actions`:

- `trigger_character` must be a single character.
- `actions` is an ordered list of named actions.

An entry can have more than one action. cmp-git runs the actions of the matching entries in config order. It stops at
the first action that handles the request.

### Pattern entries

An entry can use `pattern` in place of `trigger_character`. `pattern` is a Vim regex in the default `magic` mode. The
entry applies when the pattern matches the text before the cursor, up to the cursor. The completed text starts at the
start of the match. cmp-git also adds the patterns to the `nvim-cmp` keyword pattern.

An entry can also have `keyword_pattern`. Then cmp-git adds `keyword_pattern` to the `nvim-cmp` keyword pattern in place
of `pattern`. `nvim-cmp` filters the items on the text from the start of the keyword match.

`nvim-cmp` matches the keyword pattern on each keystroke. Use `\zs`, not a lookbehind such as `\@<=`. A lookbehind
makes Vim use its backtracking engine, and its time grows with the square of the line length.

The trailer value entry of earlier versions used a lookbehind. If an entry has that pattern and no `keyword_pattern`,
cmp-git uses the current trailer value patterns for it.

The default trailer entries come before the `:` entry. As a result, `Co-authored-by:` completes identities, not
commits.

### Built-in actions

The built-in actions are `git_commits`, `git_trailer_keys`, `git_trailer_identities`, `git_trailer_values`,
`gitlab_issues`, `gitlab_mentions`, `gitlab_change_requests`, `github_issues`, `github_change_requests`,
`github_issues_and_change_requests`, and `github_mentions`. The `git_trailer_*` actions need a `pattern` entry.

Two compatibility aliases are also available:

- `gitlab_mrs` runs `gitlab_change_requests`.
- `github_issues_and_prs` runs `github_issues_and_change_requests`.

### Callback actions

For compatibility, cmp-git also supports legacy callback actions. A callback entry has `trigger_character` and
`action`. The `action` function receives these arguments, in this order:

1. The sources (currently `git`, `gitlab`, and `github`).
2. The trigger character.
3. The completion callback.
4. The parameters that `nvim-cmp` passes to `complete`.
5. The current git info.

We recommend named `actions` for new configuration.

## Trailer completion

| You type             | Completion                                         | From                                           |
| -------------------- | -------------------------------------------------- | ---------------------------------------------- |
| `Co`                 | `Co-authored-by: `                                 | A trailer key                                  |
| `Co-authored-by: Gr` | `Co-authored-by: Grace Hopper <grace@example.com>` | A commit author or identity trailer in history |
| `Signed-off-by:`     | `Signed-off-by: Ada Lovelace <ada@example.com>`    | Your git identity                              |
| `Assisted-by: Cl`    | `Assisted-by: Claude Code`                         | An earlier `Assisted-by` value                 |

Trailer completion works only when all of these conditions are true:

- The filetype of the buffer is in `git.trailers.filetypes`.
- The cursor is on line `git.trailers.min_line` (default 3) or a later line.
- The previous line is blank or is a `Key: value` line. Line 1 counts as after a blank line.

Keys come from `git.trailers.keys.builtin` and from the last `git.trailers.keys.limit` commits.

The value of a trailer completes in one of two ways:

- For a key in `git.trailers.identities.keys`, the value completes to `Name <email>`. The identities come from your git
  identity, and from the authors and the trailers with these keys in the last `git.trailers.identities.limit` commits.
- For any other key, the value completes to the values that the same key had in the last `git.trailers.values.limit`
  commits. `Key:` with no space after the colon completes commits. For example, `Fixes:` completes commits.

Value completion stops when the typed value contains `:`, `#`, `@`, or `!` outside `<...>`. As a result, these
triggers also work in a trailer value. For example, `Fixes: #12` completes issues.

To turn off trailer completion, set `trigger_actions` without the two `pattern` entries.

If you set your own `trigger_actions`, add the two `pattern` entries from the [defaults](../README.md#config) to get
trailer completion.

## Format and sort items

Each capability, such as `git.commits` or `github.issues`, has a `format` table and a `sort_by` value.

### Format

`format` has four functions. Each function receives `trigger_char` and the item, and returns one part of the
completion item:

| Function        | Returns                                                                 |
| --------------- | ----------------------------------------------------------------------- |
| `label`         | The text in the completion menu                                         |
| `filterText`    | The text that the completion engine filters on                          |
| `insertText`    | The text that cmp-git inserts                                           |
| `documentation` | The text of the documentation window, as `{ kind = "markdown", value }` |

`trigger_char` is the trigger character, such as `#`. It can be `nil` for a pattern entry.

You can replace one function. The other functions keep their defaults. For example, this setup inserts the full SHA
of a commit and shows it in the label:

```lua
require("cmp_git").setup({
    git = {
        commits = {
            sha_length = 40,
            format = {
                label = function(_trigger_char, commit)
                    return string.format("%s: %s", commit.sha, commit.title)
                end,
            },
        },
    },
})
```

For a trigger character, `filterText` must contain that character, or the completion engine shows no items. The
default functions start `filterText` with the trigger character.

For compatibility, cmp-git also supports `filter_fn` on a provider, as an alias of `format.filterText`. A provider
`filter_fn` applies to every capability of that provider. The exception is `git.filter_fn`, which applies only to
`git.commits`.

### Item fields

| Capability                               | Fields                                                                                  |
| ---------------------------------------- | --------------------------------------------------------------------------------------- |
| `git.commits`                            | `sha`, `title`, `description`, `author_name`, `author_mail`, `commit_timestamp`, `diff` |
| `git.trailers.keys`                      | `key`, `count`, `builtin_index`                                                         |
| `git.trailers.identities`                | `name`, `email`, `source`, `is_self`, `timestamp`, `diff`                               |
| `git.trailers.values`                    | `key`, `value`, `count`, `timestamp`, `diff`                                            |
| `github.issues`, `github.pull_requests`  | The `fields` with the GitHub CLI, or the REST API fields with curl                      |
| `github.mentions`                        | `login`                                                                                 |
| `gitlab.issues`, `gitlab.merge_requests` | The GitLab API fields, such as `iid`, `title`, `description`, and `updated_at`          |
| `gitlab.mentions`                        | `username`, `name`                                                                      |

- `sha` has `git.commits.sha_length` characters (default 7). The default `insertText` inserts `sha`. The default
  `label` shows the first 7 characters.
- `author_name` and `author_mail` are the name and the email of the author, with the `.mailmap` applied.
  `commit_timestamp` is the commit date.
- GitHub issues and pull requests always have `body` and `updatedAt`.
- `diff` is the number of seconds since the commit, or since the most recent use of the identity or the value.
- `count` is the number of uses in the scanned commits.
- `builtin_index` is the position of the key in `git.trailers.keys.builtin`. It is `nil` for a key from history.
- `source` is `"author"`, the trailer key, or `"self"`. `is_self` is `true` for your git identity.

### Sort

`sort_by` sets the `sortText` of each item. It can be a function that receives the item and returns a string, or a
field name, such as `"title"`. For a field name, cmp-git uses the value of that field.

| Capability                                | Default order                                                              |
| ----------------------------------------- | -------------------------------------------------------------------------- |
| `git.commits`                             | Newest first                                                               |
| `git.trailers.keys`                       | Most used first, then the order of `keys.builtin`, then alphabetical order |
| `git.trailers.identities`                 | Most recent first. Your git identity comes first if it is not in history.  |
| `git.trailers.values`                     | Most used first, then most recent                                          |
| Issues, pull requests, and merge requests | Last updated first                                                         |
| `github.mentions`, `gitlab.mentions`      | No `sort_by`, so the items have no `sortText`                              |

### Sorting in nvim-cmp

To make `nvim-cmp` use the order of cmp-git, move `cmp.config.compare.sort_text` nearer the start of
`sorting.comparators` (a lower index). For example:

```lua
require("cmp").setup({
    -- sources and your other options
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

## Filetypes

`filetypes` lists the filetypes where cmp-git completes. To complete in all filetypes, set `filetypes = { "*" }`.

`git.trailers.filetypes` lists the filetypes where trailer completion works. It does not support `"*"`. Trailer
completion also needs the filetype in `filetypes`.

A compound filetype, such as `gitcommit.markdown`, matches when one of its parts is in the list.

## Remotes and SSH aliases

cmp-git gets the host, the owner, and the repository from the URL of a git remote. It reads the remotes in the order
of `remotes`, and uses the first URL that it can parse. `remotes` can also be a single string.

cmp-git uses the git repository of the directory of the file in the buffer. If the buffer has no file, or if that
directory is not in a git repository, cmp-git uses the working directory of Neovim.

cmp-git keeps the repository and its remote URLs for each buffer. It reads them again in these cases:

- The git config of the repository changes, for example after `git remote add`.
- The repository came from the working directory of Neovim, and that directory changes.
- cmp-git found no repository, and 5 seconds have passed.

If `enableRemoteUrlRewrites` is `true`, cmp-git reads the URLs with `git remote -v`. This command applies the
`url.<base>.insteadOf` rewrites. If it is `false`, cmp-git reads `remote.<name>.url` without rewrites.

If a remote uses a host alias from your SSH config, add the alias and the real host to `ssh_aliases`:

```lua
require("cmp_git").setup({
    ssh_aliases = {
        ["github-work"] = "github.com",
    },
})
```

With this setup, cmp-git uses `github.com` for the remote `git@github-work:owner/repo.git`. The alias must match the
full host.

If you set a default repository with `gh repo set-default`, GitHub issues, pull requests, and mentions come from that
repository. cmp-git reads the default repository once for each repository, so restart Neovim after you change it.
cmp-git does not use the default repository in an `octo` buffer.

In an `octo` buffer, cmp-git gets the owner and the repository from the buffer name. It gets the host from
`github_hostname` in the Octo config. The default host is `github.com`.

## GitHub CLI, GitLab CLI, and curl

For GitHub, cmp-git uses the GitHub CLI (`gh`). For GitLab, it uses the GitLab CLI (`glab`). If the CLI is not
installed, or if the CLI command fails, cmp-git uses curl.

The results are different in these cases:

- `github.issues.fields` and `github.pull_requests.fields` apply only to the GitHub CLI.
- `github.pull_requests.state = "merged"` works only with the GitHub CLI. The REST API returns no pull requests for
  this state.
- With curl, `github.issues` and `github.pull_requests` get at most 100 items. cmp-git requests one page, and the
  GitHub API gives at most 100 items for each page.
- With curl, the page of `github.issues` also contains pull requests. cmp-git removes them, so it can show fewer issues
  than `limit`.
- GitLab issues, merge requests, and mentions get at most 100 items, for the same reason. This limit applies to `glab`
  and to curl.

`github.issues.filter` can be `all`, `assigned`, `created`, or `mentioned`. The last three values show only the issues
that are assigned to you, that you created, or that mention you.

GitHub mentions come from the collaborators of the repository when your token can read them. Otherwise, they come from
the contributors. cmp-git gets more pages until it has `github.mentions.limit` mentions. To get all mentions, set
`github.mentions.limit = math.huge`.

## Hosted GitHub and GitLab instances

To use a hosted instance of GitHub Enterprise or GitLab, add its host to the `hosts` list of the provider:

```lua
require("cmp_git").setup({
    github = {
        hosts = { "github.mycompany.com", },
    },
    gitlab = {
        hosts = { "gitlab.mycompany.com", }
    }
})
```

The host must be the same as the host in the URL of the remote. cmp-git always adds `github.com` and `gitlab.com`.
With curl, cmp-git uses `https://<host>/api/v3` for GitHub Enterprise and `https://<host>/api/v4` for GitLab.

## Troubleshooting

If no items show, make sure that these conditions are true:

- The filetype of the buffer is in `filetypes`.
- The file is in a git repository.
- For GitHub and GitLab items, the host of the remote is in `github.hosts` or `gitlab.hosts`.
- For GitHub and GitLab items, `gh`, `glab`, or `curl` is installed.

To log missing executables, and the exit code and stderr of failed commands, set `vim.g.cmp_git_debug = true`. cmp-git
sends the messages with `vim.notify`.

cmp-git caches the items for each buffer and does not refresh them. To get new items, wipe the buffer with
`:bwipeout` and open the file again, or restart Neovim. cmp-git does not cache the result of a failed command or an
HTTP error, so the next request tries again.
