module Things
export Thing
using ..Maps

function update!(thing, map)
    subsector = Maps.point_in_subsector(thing.x, thing.y, map)
    if haskey(subsector.things_list, objectid(thing))
        return
    end
    subsector.things_list[objectid(thing)] = thing
    # blockmap is for collisions and things not moving dont need to go in.
end


end # module end