local sort = require("cmp_git.sort")

---`trigger_char` is nil for pattern trigger actions without a trigger character.
---@class cmp_git.FormatConfig<TItem>: {
---label: fun(trigger_char: string?, item: TItem): string;
---filterText: fun(trigger_char: string?, item: TItem): string;
---insertText: fun(trigger_char: string?, item: TItem): string;
---documentation: fun(trigger_char: string?, item: TItem): lsp.MarkupContent;
---}

local M = {
    git = {
        ---@type cmp_git.FormatConfig<cmp_git.Commit>
        commits = {
            label = function(_trigger_char, commit)
                return string.format("%s: %s", commit.sha:sub(0, 7), commit.title)
            end,
            filterText = function(trigger_char, commit)
                -- If the trigger char is not part of the label, no items will show up
                return string.format("%s %s %s", trigger_char, commit.sha:sub(0, 7), commit.title)
            end,
            insertText = function(_trigger_char, commit)
                return commit.sha
            end,
            documentation = function(_trigger_char, commit)
                return {
                    kind = "markdown",
                    value = string.format(
                        "# %s\n\n%s\n\nAuthored by %s (%s), committed on %s",
                        commit.title,
                        commit.description,
                        commit.author_name,
                        commit.author_mail,
                        os.date("%c", commit.commit_timestamp)
                    ),
                }
            end,
        },
        trailers = {
            ---@type cmp_git.FormatConfig<cmp_git.TrailerKey>
            keys = {
                label = function(_trigger_char, trailer)
                    return trailer.key
                end,
                filterText = function(_trigger_char, trailer)
                    return trailer.key
                end,
                insertText = function(_trigger_char, trailer)
                    return trailer.key .. ": "
                end,
                documentation = function(_trigger_char, trailer)
                    return {
                        kind = "markdown",
                        value = string.format(
                            "# %s\n\nUsed %d %s in recent commits",
                            trailer.key,
                            trailer.count,
                            trailer.count == 1 and "time" or "times"
                        ),
                    }
                end,
            },
            -- For identities and values, trigger_char is set only when the value touches the colon (`Key:` or
            -- `Key:Ad`). Then the nvim-cmp offset starts at the colon, and the inserted value needs a space after it.
            ---@type cmp_git.FormatConfig<cmp_git.TrailerIdentity>
            identities = {
                label = function(_trigger_char, identity)
                    return string.format("%s <%s>", identity.name, identity.email)
                end,
                filterText = function(trigger_char, identity)
                    if trigger_char then
                        return string.format("%s %s <%s>", trigger_char, identity.name, identity.email)
                    end
                    return string.format("%s <%s>", identity.name, identity.email)
                end,
                insertText = function(trigger_char, identity)
                    return string.format("%s%s <%s>", trigger_char and " " or "", identity.name, identity.email)
                end,
                documentation = function(_trigger_char, identity)
                    local source = identity.source
                    if identity.is_self then
                        source = "You"
                    elseif source == "author" then
                        source = "Commit author"
                    end

                    return {
                        kind = "markdown",
                        value = string.format("# %s\n\n%s\n\nFrom: %s", identity.name, identity.email, source),
                    }
                end,
            },
            ---@type cmp_git.FormatConfig<cmp_git.TrailerValue>
            values = {
                label = function(_trigger_char, trailer)
                    return trailer.value
                end,
                filterText = function(trigger_char, trailer)
                    if trigger_char then
                        return string.format("%s %s", trigger_char, trailer.value)
                    end
                    return trailer.value
                end,
                insertText = function(trigger_char, trailer)
                    return (trigger_char and " " or "") .. trailer.value
                end,
                documentation = function(_trigger_char, trailer)
                    return {
                        kind = "markdown",
                        value = string.format(
                            "# %s\n\n%s\n\nUsed %d %s in recent commits",
                            trailer.key,
                            trailer.value,
                            trailer.count,
                            trailer.count == 1 and "time" or "times"
                        ),
                    }
                end,
            },
        },
    },
    github = {
        ---@type cmp_git.FormatConfig<cmp_git.GitHub.Issue>
        issues = {
            label = function(_trigger_char, issue)
                return string.format("#%s: %s", issue.number, issue.title)
            end,
            insertText = function(_trigger_char, issue)
                return string.format("#%s", issue.number)
            end,
            filterText = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.number, issue.title)
            end,
            documentation = function(_trigger_char, issue)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.body),
                }
            end,
        },
        ---@type cmp_git.FormatConfig<cmp_git.GitHub.Mention>
        mentions = {
            label = function(_trigger_char, mention)
                return string.format("@%s", mention.login)
            end,
            insertText = function(_trigger_char, mention)
                return string.format("@%s", mention.login)
            end,
            filterText = function(_trigger_char, mention)
                return string.format("@%s", mention.login)
            end,
            documentation = function(_trigger_char, mention)
                return {
                    kind = "markdown",
                    value = string.format("# %s", mention.login),
                }
            end,
        },
        ---@type cmp_git.FormatConfig<cmp_git.GitHub.PullRequest>
        pull_requests = {
            label = function(_trigger_char, pr)
                return string.format("#%s: %s", pr.number, pr.title)
            end,
            insertText = function(_trigger_char, pr)
                return string.format("#%s", pr.number)
            end,
            filterText = function(trigger_char, pr)
                return string.format("%s %s %s", trigger_char, pr.number, pr.title)
            end,
            documentation = function(_trigger_char, pr)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", pr.title, pr.body),
                }
            end,
        },
    },
    gitlab = {
        ---@type cmp_git.FormatConfig<cmp_git.GitLab.Issue>
        issues = {
            label = function(_trigger_char, issue)
                return string.format("#%s: %s", issue.iid, issue.title)
            end,
            insertText = function(_trigger_char, issue)
                return string.format("#%s", issue.iid)
            end,
            filterText = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.iid, issue.title)
            end,
            documentation = function(_trigger_char, issue)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.description),
                }
            end,
        },
        ---@type cmp_git.FormatConfig<cmp_git.GitLab.Mention>
        mentions = {
            label = function(_trigger_char, mention)
                return string.format("@%s", mention.username)
            end,
            insertText = function(_trigger_char, mention)
                return string.format("@%s", mention.username)
            end,
            filterText = function(trigger_char, mention)
                return string.format("%s %s", trigger_char, mention.username)
            end,
            documentation = function(_trigger_char, mention)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mention.username, mention.name),
                }
            end,
        },
        ---@type cmp_git.FormatConfig<cmp_git.GitLab.MergeRequest>
        merge_requests = {
            label = function(_trigger_char, mr)
                return string.format("!%s: %s", mr.iid, mr.title)
            end,
            insertText = function(_trigger_char, mr)
                return string.format("!%s", mr.iid)
            end,
            filterText = function(trigger_char, mr)
                return string.format("%s %s %s", trigger_char, mr.iid, mr.title)
            end,
            documentation = function(_trigger_char, mr)
                return {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mr.title, mr.description),
                }
            end,
        },
    },
}

---@class cmp_git.CompletionItem : lsp.CompletionItem
---@field label string
---@field filterText string
---@field insertText string
---@field sortText string?
---@field documentation lsp.MarkupContent
---@field data any

---@class cmp_git.CompletionList
---@field items cmp_git.CompletionItem[]
---@field isIncomplete boolean

---@generic TItem
---@param config { format: cmp_git.FormatConfig<TItem>, sort_by: string | fun(item: TItem): string }
---@param trigger_char string? nil for pattern trigger actions without a trigger character
---@return cmp_git.CompletionItem
function M.item(config, trigger_char, item)
    return {
        label = config.format.label(trigger_char, item),
        filterText = config.format.filterText(trigger_char, item),
        insertText = config.format.insertText(trigger_char, item),
        sortText = sort.get_sort_text(config.sort_by, item),
        documentation = config.format.documentation(trigger_char, item),
        data = item,
    }
end

---@generic TItem
---@param config { format: cmp_git.FormatConfig<TItem>, sort_by: string | fun(item: TItem): string }
---@param trigger_char string? nil for pattern trigger actions without a trigger character
---@param items TItem[]
---@return cmp_git.CompletionItem[]
function M.items(config, trigger_char, items)
    local result = {}
    for index, item in ipairs(items) do
        result[index] = M.item(config, trigger_char, item)
    end
    return result
end

return M
