#!/usr/bin/env julia
# This file is a part of Julia. License is MIT: https://julialang.org/license

using TOML

function check_flag(flag)
    idxs = findall(flag .== ARGS)
    for idx in reverse(idxs)
        popat!(ARGS, idx)
    end
    return !isempty(idxs)
end

if check_flag("--help") || check_flag("-h")
    println("Usage: julia print_sorted_stdlibs.jl [stdlib_dir] [--exclude-jlls] [--exclude-sysimage] [--only-sysimg]")
end

# Allow users to ask for JLL or no JLLs
exclude_jlls = check_flag("--exclude-jlls")
exclude_sysimage = check_flag("--exclude-sysimage")
only_sysimage = check_flag("--only-sysimg")

# Default to the `stdlib/vX.Y` directory
STDLIB_DIR = get(ARGS, 1, joinpath(@__DIR__, "..", "usr", "share", "julia", "stdlib"))
vXYdirs = readdir(STDLIB_DIR)
if length(vXYdirs) == 1 && match(r"v\d\.\d", vXYdirs[1]) !== nothing
    STDLIB_DIR = joinpath(STDLIB_DIR, vXYdirs[1])
end

project_deps = Dict{String,Set{String}}()
for project_dir in readdir(STDLIB_DIR, join=true)
    project_file = joinpath(project_dir, "Project.toml")
    if isfile(project_file)
        project = TOML.parsefile(project_file)

        if !haskey(project, "name")
            continue
        end
        name = project["name"]
        deps = Set(collect(keys(get(project, "deps", Dict{String,String}()))))
        project_deps[name] = deps
    end
end

#println("Found $(length(keys(project_deps))) stdlib projects")

function project_depth(project)
    deps = project_deps[project]
    if isempty(deps)
        return 0
    end

    depth = 1
    while !all(isempty(project_deps[d]) for d in deps)
        depth += 1

        if depth > 100
            error("Failed to converge while finding project depth for $(project)!")
        end

        new_deps = Set{String}()
        for d in deps
            union!(new_deps, project_deps[d])
        end
        deps = new_deps
    end
    return depth
end

project_depths = Dict(p => project_depth(p) for p in keys(project_deps))

function project_isless(p1, p2)
    if project_depths[p1] != project_depths[p2]
        return isless(project_depths[p1], project_depths[p2])
    end
    return isless(p1, p2)
end

sorted_projects = sort(collect(keys(project_depths)), lt=project_isless)

if exclude_jlls
    filter!(p -> !endswith(p, "_jll"), sorted_projects)
end

if only_sysimage && exclude_sysimage
    println(stderr, "Warning: --only-sysimg and --exclude-sysimage are mutually exclusive. Prioritizing --only-sysimg.")
    exclude_sysimage = false
end

if only_sysimage || exclude_sysimage
    loaded_modules_set = Set(map(k->k.name, collect(keys(Base.loaded_modules))))

    if only_sysimage
        filter!(p -> in(p, loaded_modules_set), sorted_projects)
    else
        filter!(p -> !in(p, loaded_modules_set), sorted_projects)
    end
end

# Print out sorted projects, ready to be pasted into `sysimg.jl`
last_depth = 0
println("    # Stdlibs sorted in dependency, then alphabetical, order by contrib/print_sorted_stdlibs.jl")
if exclude_jlls
    println("    # Run with the `--exclude-jlls` option to filter out all JLL packages")
end
if only_sysimage
    println("    # Run with the `--only-sysimg` option to filter for only packages included in the system image")
end
if exclude_sysimage
    println("    # Run with the `--exclude-sysimage` option to filter out all packages included in the system image")
end
println("    stdlibs = [")
println("        # No dependencies")
for p in sorted_projects
    if project_depths[p] != last_depth
        global last_depth = project_depths[p]
        println()
        println("        # $(last_depth)-depth packages")
    end
    println("        :$(p),")
end
println("    ]")
