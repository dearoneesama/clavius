-- Runs Boogie on a core program and collects the ids of the obligations that fail. All units go to
-- one Boogie process. A unit that runs out of resources is checked again one assert at a time to name
-- the asserts that fail.
--
-- The `BOOGIE` environment variable names the Boogie executable, and `Z3` the Z3 that Boogie runs.
-- Each defaults to the program of that name on `PATH`.

local boogie_output = require 'clavius.backend.boogie.output'
local boogie_print = require 'clavius.backend.boogie.print'

--- @class BoogieRunOptions
--- @field rlimit integer|nil Z3 resource limit of each unit
--- @field nonlinear boolean|nil whether every unit may use Z3's nonlinear arithmetic, not only nonlinear ones

local M = {}

--- @param s string
--- @return string
local function shell_quote(s)
    return ("'%s'"):format((s:gsub("'", "'\\''")))
end

--- Runs Boogie on one program and returns everything it prints. Unless `nonlinear` is set, Z3's
--- nonlinear arithmetic is off, so a product of two variables is an opaque term outside nonlinear units.
--- With it set, Z3 runs with its default options.
--- @param bpl string
--- @param nonlinear boolean
--- @return string
local function run_boogie(bpl, nonlinear)
    -- Boogie only reads files whose name ends in .bpl
    local base = os.tmpname()
    local path = base .. '.bpl'
    local f = assert(io.open(path, 'wb'))
    f:write(bpl)
    f:close()
    local args = { shell_quote(os.getenv 'BOOGIE' or 'boogie'), '/errorLimit:0' }
    if not nonlinear then
        -- the older arithmetic solver, since the default one ignores `smt.arith.nl`
        args[#args + 1] = '/proverOpt:O:smt.arith.solver=2'
        -- no second solver for a query with no quantifiers that comes back unknown, since it would solve it
        args[#args + 1] = '/proverOpt:O:combined_solver.solver2_unknown=0'
        args[#args + 1] = '/proverOpt:O:smt.arith.nl=false'
    end
    local z3 = os.getenv 'Z3'
    if z3 then
        args[#args + 1] = shell_quote(('/proverOpt:PROVER_PATH=%s'):format(z3))
    end
    args[#args + 1] = shell_quote(path)
    local pipe = assert(io.popen(('%s 2>&1'):format(table.concat(args, ' '))))
    local text = pipe:read '*a'
    pipe:close()
    os.remove(path)
    os.remove(base)
    return text
end

--- Prints the declarations and units, runs Boogie on them and parses its output.
--- @param core CoreArena
--- @param decls NodeId[]
--- @param units NodeId[]
--- @param print_opts BoogiePrintOptions
--- @param nonlinear boolean
--- @return BoogieOutput|nil result
--- @return string|nil err
local function check_once(core, decls, units, print_opts, nonlinear)
    local text = run_boogie(boogie_print.program(core, decls, units, print_opts), nonlinear)
    local result, err = boogie_output.parse(text)
    if not result then
        return nil, ('%s:\n%s'):format(err, text)
    end
    return result, nil
end

--- Verifies the units of a valid core program. Returns the ids of the failing obligations in
--- ascending order, or nil and an error with Boogie's output when there is no verdict.
--- @param core CoreArena
--- @param decls NodeId[]
--- @param units NodeId[]
--- @param opts BoogieRunOptions|nil
--- @return integer[]|nil failed
--- @return string|nil err
function M.check(core, decls, units, opts)
    -- nothing to check
    if #units == 0 then
        return {}, nil
    end
    local rlimit = opts and opts.rlimit
    local nonlinear = (opts and opts.nonlinear) == true
    local first, err = check_once(core, decls, units, { rlimit = rlimit }, nonlinear)
    if not first then
        return nil, err
    end
    local failed = first.failed
    -- Boogie checks each unit as one query. When that query runs out of resources, Boogie reports
    -- none of the unit's failing asserts. The rerun gives each assert of those units its own query and
    -- resource limit, so it names every failing assert. An assert that runs out of resources on its
    -- own counts as failing.
    if #first.out_of_resource > 0 then
        local split, rerun = {}, {}
        for _, name in ipairs(first.out_of_resource) do
            split[name] = true
        end
        for _, id in ipairs(units) do
            local u = core.nodes[id]
            if u.tag == 'Unit' and split[u.name] then
                rerun[#rerun + 1] = id
            end
        end
        local second, err2 = check_once(core, decls, rerun, { rlimit = rlimit, split = split }, nonlinear)
        if not second then
            return nil, err2
        end
        if #second.out_of_resource > 0 then
            return nil, ('Boogie ran out of resources checking each assert of %s on its own'):format(second.out_of_resource[1])
        end
        for _, id in ipairs(second.failed) do
            failed[#failed + 1] = id
        end
    end
    -- one obligation id can label several asserts, and Boogie prints it once per failing assert
    table.sort(failed)
    local unique = {}
    for _, id in ipairs(failed) do
        if unique[#unique] ~= id then
            unique[#unique + 1] = id
        end
    end
    return unique, nil
end

return M
