local sort = require("cmp_git.sort")

local M = {
    git = {
        commits = {
            label = function(trigger_char, commit)
                return string.format("%s: %s", commit.sha, commit.title)
            end,
            filterText = function(trigger_char, commit)
                -- If the trigger char is not part of the label, no items will show up
                return string.format("%s %s %s", trigger_char, commit.sha, commit.title)
            end,
            insertText = function(trigger_char, commit)
                return commit.sha
            end,
            documentation = function(trigger_char, commit)
                return {
                    kind = "markdown",
                    value = string.format(
                        "# %s\n\n%s\n\nCommited by %s (%s) on %s",
                        commit.title,
                        commit.description,
                        commit.author_name,
                        commit.author_mail,
                        os.date("%c", commit.commit_timestamp)
                    ),
                }
            end,
        },
    },
    github = {
        issues = {
            label = function(trigger_char, issue)
                return string.format("#%s: %s", issue.number, issue.title)
            end,
            insertText = function(trigger_char, issue)
                return string.format("#%s", issue.number)
            end,
            filterText = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.number, issue.title)
            end,
            documentation = function(trigger_char, issue)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.body),
                }
            end,
        },
        mentions = {
            label = function(trigger_char, mention)
                return string.format("@%s", mention.login)
            end,
            insertText = function(trigger_char, mention)
                return string.format("@%s", mention.login)
            end,
            filterText = function(trigger_char, mention)
                return string.format("@%s", mention.login)
            end,
            documentation = function(trigger_char, mention)
                return {
                    kind = "markdown",
                    value = string.format("# %s", mention.login),
                }
            end,
        },
        pull_requests = {
            label = function(trigger_char, pr)
                return string.format("#%s: %s", pr.number, pr.title)
            end,
            insertText = function(trigger_char, pr)
                return string.format("#%s", pr.number)
            end,
            filterText = function(trigger_char, pr)
                return string.format("%s %s %s", trigger_char, pr.number, pr.title)
            end,
            documentation = function(trigger_char, pr)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", pr.title, pr.body),
                }
            end,
        },
    },
    gitlab = {
        issues = {
            label = function(trigger_char, issue)
                return string.format("#%s: %s", issue.iid, issue.title)
            end,
            insertText = function(trigger_char, issue)
                return string.format("#%s", issue.iid)
            end,
            filterText = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.iid, issue.title)
            end,
            documentation = function(trigger_char, issue)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.description),
                }
            end,
        },
        mentions = {
            label = function(trigger_char, mention)
                return string.format("@%s", mention.username)
            end,
            insertText = function(trigger_char, mention)
                return string.format("@%s", mention.username)
            end,
            filterText = function(trigger_char, mention)
                return string.format("%s %s", trigger_char, mention.username)
            end,
            documentation = function(trigger_char, mention)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mention.username, mention.name),
                }
            end,
        },
        merge_requests = {
            label = function(trigger_char, mr)
                return string.format("!%s: %s", mr.iid, mr.title)
            end,
            insertText = function(trigger_char, mr)
                return string.format("!%s", mr.iid)
            end,
            filterText = function(trigger_char, mr)
                return string.format("%s %s %s", trigger_char, mr.iid, mr.title)
            end,
            documentation = function(trigger_char, mr)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mr.title, mr.description),
                }
            end,
        },
    },
}

M.item = function(config, trigger_char, item)
    return {
        label = config.format.label(trigger_char, item),
        filterText = config.format.filterText(trigger_char, item),
        insertText = config.format.insertText(trigger_char, item),
        sortText = sort.get_sort_text(config.sort_by, item),
        documentation = config.format.documentation(trigger_char, item),
        data = item,
    }
end

return M
