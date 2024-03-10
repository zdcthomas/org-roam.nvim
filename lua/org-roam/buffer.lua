-------------------------------------------------------------------------------
-- BUFFER.LUA
--
-- Supports operating and retrieving information on org-roam buffers.
-------------------------------------------------------------------------------

local IntervalTree = require("org-roam.core.utils.tree.interval")
local Scanner = require("org-roam.core.scanner")

---@private
---@class org-roam.buffer.CacheItem
---@field tree org-roam.core.utils.tree.IntervalTree|nil
---@field tick integer

---Internal cache of buffer -> cache of node ids used to look up
---nodes within buffers.
---@type table<integer, org-roam.buffer.CacheItem>
local CACHE = {}

-------------------------------------------------------------------------------
-- PUBLIC
-------------------------------------------------------------------------------

---@class org-roam.Buffer
local M = {}

---Returns a copy of the node under cursor of the current buffer.
---
---NOTE: This caches the state of the buffer (nodes), returning the pre-cached
---      result when possible. The cache is discarded whenever the current
---      buffer is detected as changed as seen via `b:changedtick`.
---
---@param cb fun(id:org-roam.core.database.Node|nil)
function M.node_under_cursor(cb)
    local bufnr = vim.api.nvim_win_get_buf(0)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local offset = vim.api.nvim_buf_get_offset(bufnr, cursor[1] - 1) + cursor[2]

    ---@return org-roam.core.database.Node|nil
    local function get_node()
        ---@type org-roam.buffer.CacheItem|nil
        local cache = CACHE[bufnr]
        ---@type integer
        local tick = vim.b[bufnr].changedtick

        local tree = cache and cache.tree
        local is_dirty = tick ~= (cache and cache.tick)

        -- If the buffer has changed or we had no cache, update
        if is_dirty or not cache then
            -- TODO: Can we just index by filename in the database
            --       and `find_by_index` to get nodes connected to the
            --       file represented by the buffer to build this
            --       up versus re-parsing the buffer?
            local contents = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
            local scan = Scanner.scan(contents)

            if #scan.nodes > 0 then
                tree = IntervalTree:from_list(
                ---@param node org-roam.core.database.Node
                    vim.tbl_map(function(node)
                        return {
                            node.range.start.offset,
                            node.range.end_.offset,
                            node,
                        }
                    end, scan.nodes)
                )
            end

            -- Update cache pointer to reflect the current state
            CACHE[bufnr] = {
                tree = tree,
                tick = tick,
            }
        end

        -- Find id of deepest node containing the offset
        if tree then
            return tree:find_last_data({ offset, match = "contains" })
        end
    end

    vim.schedule(function()
        cb(get_node())
    end)
end

return M
