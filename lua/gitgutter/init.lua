local M = {}

M.config = {}

-- If no_render_signs is set, the variable maps the buffer number
-- to the map of line numbers to (unused) sign_text and sign_hl_group
-- values.
M.state = {}

local config_defaults = {
  -- Extmarks/signs symbols.
  signs = {
    add          = "┃",  -- "+"
    change       = "┃",  -- "~"
    delete       = "_",  -- "_"
    delete_above = "‾",  -- "-"
  },

  -- Extmarks priority.
  extmarks_priority = 10,

  -- Delay before updating after a change in the insert mode.
  debounce_ms = 150,

  -- Disable rendering of extmarks/signs.
  no_render_signs = false,
}

local ns_id = vim.api.nvim_create_namespace("GitGutter_extmarks_ns")
local timer = vim.loop.new_timer()

-- Helper to parse unified diff hunks.
local function parse_diff_line(line)
  if not vim.startswith(line, "@@") then return nil end

  local new_info = string.match(line, "%+(%d+,?%d*)")
  if not new_info then return nil end

  local parts = vim.split(new_info, ",")
  local start_line = tonumber(parts[1])
  local count = tonumber(parts[2]) or 1

  if count == 0 then
    return { type = "delete", line = start_line }
  elseif string.find(line, "%-%d+,0") then
    return { type = "add", line = start_line, count = count }
  else
    return { type = "change", line = start_line, count = count }
  end
end

-- Core update function.
local function update_gutter()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  if file_path == "" or vim.bo[bufnr].buftype ~= "" then return end

  -- Get the content of the buffer.
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local buffer_text = table.concat(buffer_lines, "\n") .. "\n"

  local file_dir = vim.fs.dirname(file_path)
  local file_name = vim.fs.basename(file_path)

  -- Fetch the HEAD version of the file in the buffer.
  vim.system(
    { "git", "show", ":./" .. file_name },
    { cwd = file_dir },
    function(result)
      if result.code ~= 0 or not result.stdout then return end

      local git_text = result.stdout

      -- Compare the HEAD and the buffer.
      local diff_output = vim.diff(git_text, buffer_text, { result_type = "unified" })

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end

        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
        M.state[bufnr] = {}

        if not diff_output or diff_output == "" then return end

        local total_lines = vim.api.nvim_buf_line_count(bufnr)

        -- helper function
        local function apply_mark(line, text, hl)
          if line < 0 or line >= total_lines then return end

          local extmark = { sign_text = "", }

          if M.config.no_render_signs then
            M.state[bufnr][line] = {
              sign_text = text,
              sign_hl_group = hl,
            }
          else
            extmark = {
              sign_text = text,
              sign_hl_group = hl,
              priority = M.config.extmarks_priority,
            }
          end

          vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, extmark)
        end

        local lines = vim.split(diff_output, "\n")

        for _, line in ipairs(lines) do
          local hunk = parse_diff_line(line)
          if hunk then

            if hunk.type == "add" then
              for i = 0, hunk.count - 1 do
                apply_mark(hunk.line + i - 1, M.config.signs.add, "GitGutterAdd")
              end
            elseif hunk.type == "change" then
              for i = 0, hunk.count - 1 do
                apply_mark(hunk.line + i - 1, M.config.signs.change, "GitGutterChange")
              end
            elseif hunk.type == "delete" then
              if hunk.line == 0 then
                apply_mark(0, M.config.signs.delete_above, "GitGutterDelete")
              else
                apply_mark(hunk.line - 1, M.config.signs.delete, "GitGutterDelete")
              end
            end

          end
        end
      end)
    end
  )
end

function M.setup(config)
  -- Merge the user and default configuration.
  M.config = vim.tbl_deep_extend("force", config_defaults, config or {})

  vim.cmd([[
    highlight GitGutterAdd    guifg=#00FF00 ctermfg=Green
    highlight GitGutterChange guifg=#FFFF00 ctermfg=Yellow
    highlight GitGutterDelete guifg=#FF0000 ctermfg=Red
  ]])

  local group = vim.api.nvim_create_augroup("GitGutterGroup", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function()
      update_gutter()
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function()
      timer:stop()
      timer:start(M.config.debounce_ms, 0, vim.schedule_wrap(function()
        update_gutter()
      end))
    end,
  })
end

return M
