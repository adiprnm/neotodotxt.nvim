local neotodotxt = {}
local config = {}

local function created_date(line)
  if line:match("^x%s") then
    _, created = line:match("^x%s+(%d%d%d%d%-%d%d%-%d%d)%s+(%d%d%d%d%-%d%d%-%d%d)")
  else
    line = string.gsub(line, "^%(%u%)%s+", '', 1)
    created = line:match("^%d%d%d%d%-%d%d%-%d%d")
  end
  return created
end

local function due_date(line)
  local due = line:match("due:(%d%d%d%d%-%d%d%-%d%d)")
  return due or "1970-01-01"
end

local function project(line)
  return line:match("%@%S+") or "zzzz"
end

local function context(line)
  return line:match("%+%S+") or "zzzz"
end

local function priority(line)
  return line:match("^%(%u%)") or "(Z)"
end

local function get_active_todos()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local todos = {}
  for _, line in ipairs(lines) do
    if not line:match("^x ") then
      table.insert(todos, line)
    end
  end
  return todos
end

local function get_done_todos()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local todos = {}
  for _, line in ipairs(lines) do
    if line:match("^x ") then
      table.insert(todos, line)
    end
  end
  return todos
end

local function sort_tasks_by(sort_column, sort_direction)
  sort_direction = sort_direction or "asc"

  local active_todos = get_active_todos()
  local done_todos = get_done_todos()

  if sort_direction == "asc" then
    table.sort(active_todos, function(a, b)
      return sort_column(a) < sort_column(b)
    end)
  else
    table.sort(active_todos, function(a, b)
      return sort_column(a) > sort_column(b)
    end)
  end

  if (sort_direction == "asc") then
    table.sort(done_todos, function(a, b)
      return sort_column(a) < sort_column(b)
    end)
  else
    table.sort(done_todos, function(a, b)
      return sort_column(a) > sort_column(b)
    end)
  end

  local sorted = {}
  for _, line in ipairs(active_todos) do table.insert(sorted, line) end
  for _, line in ipairs(done_todos) do table.insert(sorted, line) end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, sorted)
end

function neotodotxt.sort_by_due_date()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  table.sort(lines, function(a, b)
    local due_a = extract_due_date(a) or "9999-12-31"
    local due_b = extract_due_date(b) or "9999-12-31"
    return due_a < due_b
  end)

  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

function neotodotxt.open_todo_file()
  local todo_path = vim.fn.expand(config.todotxt_path)
  vim.cmd("edit " .. todo_path)
end

function neotodotxt.open_done_todo_file()
  local todo_path = vim.fn.expand(config.donetxt_path)
  vim.cmd("edit " .. todo_path)
end

function neotodotxt.sort_by_priority()
  sort_tasks_by(priority)
end

function neotodotxt.sort_by_created_date()
  sort_tasks_by(created_date, "desc")
end

function neotodotxt.sort_by_due_date()
  sort_tasks_by(due_date, "desc")
end

function neotodotxt.sort_by_project()
  sort_tasks_by(project)
end

function neotodotxt.sort_by_context()
  sort_tasks_by(context)
end

function neotodotxt.toggle_state()
  local current_line = vim.api.nvim_get_current_line()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local new_line = ""
  local priority_text = ""
  local completed_at = ""

  if current_line:find("^x%s+") then
    local priority = current_line:match("pri:%u")
    if priority then
      local new_priority = priority:match("%u")
      current_line = string.gsub(current_line, " pri:%u", '', 1)
      priority_text = "(" .. new_priority .. ") "
    end
    current_line = string.gsub(current_line, "^x%s+", '', 1)
    current_line = string.gsub(current_line, "^%d%d%d%d%-%d%d%-%d%d%s+", '', 1)
    new_line = priority_text .. current_line
  else
    local priority = current_line:match("^%(%u%)")
    if priority then
      local priority_without_bracket = string.match(priority, "%u")
      current_line = string.gsub(current_line, "^%([A-F]%) ", '')
      priority_text = " pri:" .. priority_without_bracket
    end
    completed_at = os.date("%Y-%m-%d")
    new_line = "x " .. completed_at .. " " ..  current_line .. priority_text
  end

  vim.api.nvim_buf_set_lines(0, row-1, row, true, {new_line})
end

function neotodotxt.create_task()
  vim.ui.input({ prompt = "Enter task name: " }, function(task_name)
    if task_name and task_name:match("%S") then
      local date = os.date("%Y-%m-%d")
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, 0, false, { date .. " " .. task_name })
      print("✅ Task added: " .. task_name)
    else
      print("❌ Task not added (empty or canceled)")
    end
  end)
end

function neotodotxt.move_to_done()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]

  if not line or not line:match("^x%s") then
    print("❌ Task is not done yet")
    return
  end

  local f = io.open(config.donetxt_path, "a")
  if f then
    f:write(line .. "\n")
    f:close()
  else
    print("❌ Failed to write to " .. config.donetxt_path)
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, {})
  print("✅ Task moved to " .. config.donetxt_path)
end

function neotodotxt.setup(opts)
	opts = opts or {}
	config.todotxt_path = opts.todotxt_path or vim.env.HOME .. "/Documents/todo.txt"
	config.donetxt_path = opts.donetxt_path or vim.env.HOME .. "/Documents/done.txt"

	if vim.fn.filereadable(config.todotxt_path) == 0 then
		vim.fn.writefile({}, config.todotxt_path)
	end

	if vim.fn.filereadable(config.donetxt_path) == 0 then
		vim.fn.writefile({}, config.donetxt_path)
	end
end

return neotodotxt
