local M = {}

local git = require("neogit.lib.git")
local util = require("neogit.lib.util")
local input = require("neogit.lib.input")

local LogViewBuffer = require("neogit.buffers.log_view")
local ReflogViewBuffer = require("neogit.buffers.reflog_view")
local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

local a = require("plenary.async")

--- Runs `git log` and parses the commits
---@param popup table Contains the argument list
---@param flags table extra CLI flags like --branches or --remotes
---@return CommitLogEntry[]
local function commits(popup, flags)
  return git.log.list(
    util.merge(popup:get_arguments(), flags),
    popup:get_internal_arguments().graph,
    popup.state.env.files,
    false,
    popup:get_internal_arguments().color
  )
end

---@param popup table
---@param flags table
---@return fun(offset: number): CommitLogEntry[]
local function fetch_more_commits(popup, flags)
  return function(offset)
    return commits(popup, util.merge(flags, { ("--skip=%s"):format(offset) }))
  end
end

function M.log_current(popup)
  LogViewBuffer.new(
    commits(popup, {}),
    popup:get_internal_arguments(),
    popup.state.env.files,
    fetch_more_commits(popup, {}),
    "Commits in " .. (git.branch.current() or ("(detached) " .. git.log.message("HEAD"))),
    git.remote.list()
  ):open()
end

function M.log_related(popup)
  local flags = git.branch.related()
  LogViewBuffer.new(
    commits(popup, flags),
    popup:get_internal_arguments(),
    popup.state.env.files,
    fetch_more_commits(popup, flags),
    "Commits in " .. table.concat(flags, ", "),
    git.remote.list()
  ):open()
end

function M.log_head(popup)
  local flags = { "HEAD" }
  LogViewBuffer.new(
    commits(popup, flags),
    popup:get_internal_arguments(),
    popup.state.env.files,
    fetch_more_commits(popup, flags),
    "Commits in HEAD",
    git.remote.list()
  ):open()
end

function M.log_local_branches(popup)
  local flags = { git.branch.is_detached() and "" or "HEAD", "--branches" }
  LogViewBuffer.new(
    commits(popup, flags),
    popup:get_internal_arguments(),
    popup.state.env.files,
    fetch_more_commits(popup, flags),
    "Commits in --branches",
    git.remote.list()
  ):open()
end

function M.log_other(popup)
  local options = util.merge(git.refs.list_branches(), git.refs.heads(), git.refs.list_tags())
  local branch = FuzzyFinderBuffer.new(options):open_async()
  if branch then
    local flags = { branch }
    LogViewBuffer.new(
      commits(popup, flags),
      popup:get_internal_arguments(),
      popup.state.env.files,
      fetch_more_commits(popup, flags),
      "Commits in " .. branch,
      git.remote.list()
    ):open()
  end
end

function M.log_all_branches(popup)
  local flags = { git.branch.is_detached() and "" or "HEAD", "--branches", "--remotes" }
  LogViewBuffer.new(
    commits(popup, flags),
    popup:get_internal_arguments(),
    popup.state.env.files,
    fetch_more_commits(popup, flags),
    "Commits in --branches --remotes",
    git.remote.list()
  ):open()
end

function M.log_all_references(popup)
  local flags = { git.branch.is_detached() and "" or "HEAD", "--all" }
  LogViewBuffer.new(
    commits(popup, flags),
    popup:get_internal_arguments(),
    popup.state.env.files,
    fetch_more_commits(popup, flags),
    "Commits in --all",
    git.remote.list()
  ):open()
end

function M.log_matching_branches(popup)
  local all_branches = git.refs.list_branches()
  local branch_set = {}
  for _, b in ipairs(all_branches) do
    branch_set[b] = true
  end

  -- Default to master or main if present, with a trailing space so the user
  -- can immediately append more patterns without having to move the cursor
  local default_pattern = branch_set["master"] and "master "
    or branch_set["main"] and "main "
    or nil

  local text_input = input.get_user_input(
    "Branches (names or globs, space-separated)",
    { default = default_pattern }
  )
  if not text_input then
    return
  end

  local flags = {}
  local labels = {}

  for _, p in ipairs(vim.split(text_input, " ", { trimempty = true })) do
    if p:find("[*?[]") then
      table.insert(flags, "--branches=" .. p)
      table.insert(flags, "--remotes=*/" .. p)
    else
      table.insert(flags, p)
    end
    table.insert(labels, p)
  end

  LogViewBuffer.new(
    commits(popup, flags),
    popup:get_internal_arguments(),
    popup.state.env.files,
    fetch_more_commits(popup, flags),
    "Commits in " .. table.concat(labels, " "),
    git.remote.list()
  ):open()
end

function M.reflog_current(popup)
  ReflogViewBuffer.new(
    git.reflog.list(git.branch.current(), popup:get_arguments()),
    "Reflog for " .. git.branch.current()
  )
    :open()
end

function M.reflog_head(popup)
  ReflogViewBuffer.new(git.reflog.list("HEAD", popup:get_arguments()), "Reflog for HEAD"):open()
end

function M.reflog_other(popup)
  local branch = FuzzyFinderBuffer.new(git.refs.list_local_branches()):open_async()
  if branch then
    ReflogViewBuffer.new(git.reflog.list(branch, popup:get_arguments()), "Reflog for " .. branch):open()
  end
end

-- TODO: Prefill the fuzzy finder with the filepath under cursor, if there is one
---comment
function M.limit_to_files()
  local fn = function(popup, option)
    if option.value ~= "" then
      popup.state.env.files = nil
      return ""
    end

    local eventignore = vim.o.eventignore
    vim.o.eventignore = "WinLeave"
    local files = FuzzyFinderBuffer.new(git.files.all_tree { with_dir = true }):open_async {
      allow_multi = true,
      refocus_status = false,
    }
    vim.o.eventignore = eventignore

    if not files or vim.tbl_isempty(files) then
      popup.state.env.files = nil
      return ""
    end

    popup.state.env.files = files
    files = util.map(files, function(file)
      return string.format([[ "%s"]], file)
    end)

    return table.concat(files, "")
  end

  return a.wrap(fn, 2)
end

return M
