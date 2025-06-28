

module Maps
    using ..Geometry
    using ..Wad: WadData, getlump_directory_index, getlump_data, getlump_directory_index
    using ..Collision
    export Vertex,
    LineDef,
    Node,
    SubSector,
    Seg, 
    Sector,
    SideDef,
    Map,
    readmap!,
    get_node,
    get_vertex,
    get_subsector,
    get_seg,
    get_seg_sectors,
    get_sidedef,
    get_sector,
    get_linedef,
    get_player,
    get_subsector_height,
    SUB_SECTOR_INDENTIFIER,
    point_in_subsector

    const SUB_SECTOR_INDENTIFIER::UInt16 = 0x8000
    const MAP_THINGS_OFFSET::Int32 = 1
    const MAP_LINEDEFS_OFFSET::Int32 = 2
    const MAP_SIDEDEFS_OFFSET::Int32 = 3
    const MAP_VERTEX_OFFSET::Int32 = 4
    const MAP_SEGS_OFFSET::Int32 = 5
    const MAP_SUBSECTORS_OFFSET::Int32 = 6
    const MAP_NODES_OFFSET::Int32 = 7
    const MAP_SECTORS_OFFSET::Int32 = 8
    const MAP_REJECT_OFFSET::Int32 = 9
    const MAP_BLOCKMAP_OFFSET::Int32 = 10

    const LINE_DEF_BLOCKING::Int32 = 1
    const LINE_DEF_BLOCK_MONSTERS::Int32 = 2
    const LINE_DEF_TWO_SIDED::Int32 = 4
    const LINE_DEF_DONT_PEG_TOP::Int32 = 8
    const LINE_DEF_DONT_PEG_BOTTOM ::Int32= 16
    const LINE_DEF_SECRET::Int32 = 32
    const LINE_DEF_SOUND_BLOCK ::Int32= 64
    const LINE_DEF_DONT_DRAW::Int32 = 128
    const LINE_DEF_MAPPED::Int32 = 256
   
    struct Vertex
        x::Int16
        y::Int16
    end

    struct LineDef
        startvertex::UInt16
        endvertex::UInt16
        flags::UInt16
        linetype::UInt16
        sectortag::UInt16
        rightsidedef::UInt16 #front
        leftsidedef::UInt16 #back
    end

    struct Node
        x_partition_start::Int16
        y_partition_start::Int16
        delta_x_partition::Int16
        delta_y_partition::Int16
        right_bounding_box::Tuple{Int16,Int16,Int16,Int16} #front
        left_bounding_box::Tuple{Int16,Int16,Int16,Int16} #back
        right_child::Int16
        left_child::Int16
    end

    struct Seg
        start_vertex::Int16
        end_vertex::Int16
        angle::Int16
        lindef::Int16
        direction::Int16
        offset::Int16
    end

    struct Thing 
        x::Int16
        y::Int16
        angle::Int16
        type::Int16
        flags::Int16
    end

    struct SubSector 
        seg_count::Int16
        first_seg::Int16
        things_list::Dict{Any, Thing}
    end

    struct Sector 
        floor_height::Int16
        ceiling_height::Int16
        floor_texture::String
        ceiling_texture::String
        light_level::Int16
        special_type::Int16
        tag::Int16
    end

    mutable struct SideDef 
        x_offset::Int16
        y_offset::Int16
        upper_texture::String
        lower_texture::String
        middle_texture::String
        sector::Int16
    end

    struct BlockmapHeader
        x_origin::Int16
        y_origin::Int16
        columns::Int16
        rows::Int16
    end

    struct Blockmap
        header::BlockmapHeader
        offsets::Vector{Int16} # offsets are relative to blockmap lump
        blocklists::Vector{Vector{Int16}} #list of linedefs in blockmap section
    end

    mutable struct Map
        name::String
        vertexes::Vector{Vertex}
        linedefs::Vector{LineDef}
        things::Vector{Thing}
        segs::Vector{Seg}
        nodes::Vector{Node}
        subsectors::Vector{SubSector}
        sectors::Vector{Sector}
        sidedefs::Vector{SideDef}
        blockmap::Blockmap
        Map() = new()
    end

    function addvertex!(map::Map, vertex::Vertex)
        push!(map.vertexes, vertex)
    end

    function addlinedef!(map::Map, linedef::LineDef)
        push!(map.linedefs, linedef)
    end

    function addthing!(map::Map, thing::Thing)
        push!(map.things, thing)
    end

    function addseg!(map::Map, seg::Seg)
        push!(map.segs, seg)
    end

    function addnode!(map::Map, node::Node)
        push!(map.nodes, node)
    end

    function addsubsector!(map::Map, subsector::SubSector)
        push!(map.subsectors, subsector)
    end

    function addsector!(map::Map, sector::Sector)
        push!(map.sectors, sector)
    end

    function addsidedef!(map::Map, sidedef::SideDef)
        push!(map.sidedefs, sidedef)
    end

    function read_all_vertex!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            vertex = readvertex!(bytes)
            addvertex!(map, vertex)
        end

    end

    function readvertex!(bytes::IOBuffer)
        x = read(bytes, Int16)
        y = read(bytes, Int16)
        return Vertex(x, y) 
    end

    function read_all_linedef!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            linedef = read_linedef!(bytes)
            addlinedef!(map, linedef)
        end
    end

    function read_linedef!(bytes::IOBuffer)
        startvertex = read(bytes, UInt16)
        endvertex = read(bytes, UInt16)
        flags = read(bytes, UInt16)
        linetype = read(bytes, UInt16)
        sectortag = read(bytes, UInt16)
        rightsidedef = read(bytes, UInt16)
        leftsidedef = read(bytes, UInt16)
        return LineDef(startvertex, endvertex, flags, linetype, sectortag,rightsidedef, leftsidedef)
    end

    function read_all_segs!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            seg = read_seg!(bytes)
            addseg!(map, seg)
        end
    end

    function read_seg!(bytes::IOBuffer)
        start_vertex = read(bytes, Int16)
        end_vertex = read(bytes, Int16)
        angle = read(bytes, Int16)
        angle = trunc(Int16, round(Geometry.convert_angle_from_bams(Int(angle))))
        lindef = read(bytes, Int16)
        direction = read(bytes, Int16)
        offset = read(bytes, Int16)
        return Seg(start_vertex, end_vertex, angle, lindef, direction, offset)
    end

    function read_all_nodes!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            node = read_node!(bytes)
            addnode!(map, node)
        end
    end

    function read_node!(bytes::IOBuffer)
        x_partition_start = read(bytes, Int16)
        y_partition_start = read(bytes, Int16)
        delta_x_partition = read(bytes, Int16)
        delta_y_partition = read(bytes, Int16)
        right_bounding_box_1 = read(bytes, Int16)
        right_bounding_box_2 = read(bytes, Int16)
        right_bounding_box_3 = read(bytes, Int16)
        right_bounding_box_4 = read(bytes, Int16)
        left_bounding_box_1 = read(bytes, Int16)
        left_bounding_box_2 = read(bytes, Int16)
        left_bounding_box_3 = read(bytes, Int16)
        left_bounding_box_4 = read(bytes, Int16)
        right_child = read(bytes, Int16)
        left_child = read(bytes, Int16)
        
        return Node(x_partition_start, 
                    y_partition_start, 
                    delta_x_partition, 
                    delta_y_partition, 
                    (right_bounding_box_1, right_bounding_box_2, right_bounding_box_3, right_bounding_box_4), 
                    (left_bounding_box_1, left_bounding_box_2, left_bounding_box_3, left_bounding_box_4), 
                    right_child, 
                    left_child)
    end

    function read_all_things!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            thing = read_thing!(bytes)
            addthing!(map, thing)
        end
    end

    function read_thing!(bytes::IOBuffer)
        x = read(bytes, Int16)
        y = read(bytes, Int16)
        angle = read(bytes, Int16)
        type = read(bytes, Int16)
        flags = read(bytes, Int16)
        return Thing(x, y, angle, type, flags)
    end

    function read_all_subsectors!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            subsector = read_subsector!(bytes)
            addsubsector!(map, subsector)
        end
    end

    function read_subsector!(bytes::IOBuffer)
        seg_count = read(bytes, Int16)
        first_seg = read(bytes, Int16)
        return SubSector(seg_count, first_seg, Dict())
    end

    function read_all_sectors!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            sector = read_sector!(bytes)
            addsector!(map, sector)
        end
    end

    function read_sector!(bytes::IOBuffer)
        floor_height = read(bytes, Int16)
        ceiling_height = read(bytes, Int16)
        floor_texture = strip(String(read(bytes,8)),'\0')
        ceiling_texture  = strip(String(read(bytes,8)),'\0')
        light_level = read(bytes, Int16)
        special_type = read(bytes, Int16)
        tag = read(bytes, Int16)
        return Sector(floor_height, ceiling_height, floor_texture, ceiling_texture, light_level, special_type, tag)
    end

    function read_all_sidedefs!(bytes::IOBuffer, map::Map)
        while !eof(bytes)
            sidedef = read_sidedef!(bytes)
            addsidedef!(map, sidedef)
        end
    end

    function read_sidedef!(bytes::IOBuffer)
        x_offset = read(bytes, Int16)
        y_offset = read(bytes, Int16)
        upper_texture = strip(String(read(bytes,8)),'\0')
        lower_texture  = strip(String(read(bytes,8)),'\0')
        middle_texture  = strip(String(read(bytes,8)),'\0')
        sector = read(bytes, Int16)
        return SideDef(x_offset, y_offset, upper_texture, lower_texture, middle_texture, sector)
    end

    function read_blockmap_header!(bytes)
        x_origin = read(bytes, Int16)
        y_origin = read(bytes, Int16)
        columns = read(bytes, Int16)
        rows = read(bytes, Int16)
        return BlockmapHeader(x_origin, y_origin, columns, rows)
    end

    function read_block_lists!(bytes::IOBuffer, offsets)
        blocklists = []
        for offset in offsets
            number_of_bytes_to_skip = offset * 2
            seek(bytes, number_of_bytes_to_skip)
            blocklist = []
            while true
                linedef_in_grid = read(bytes, Int16)
                if linedef_in_grid == -1
                    break
                end
                push!(blocklist, linedef_in_grid)
            end
            push!(blocklists, blocklist)
        end
        return blocklists
    end

    function read_blockmap!(bytes::IOBuffer, map)
        blockmap_header = read_blockmap_header!(bytes)
        number_of_blocks = blockmap_header.columns * blockmap_header.rows
        offsets = []
        for block in 1:number_of_blocks
            push!(offsets, read(bytes, Int16))
        end
        blocklists = read_block_lists!(bytes, offsets)
        return Blockmap(blockmap_header, offsets, blocklists)
    end


    function readmap!(wad::WadData, mapname::String)
        map = Map() # TODO fix this with constructors
        map.vertexes = []
        map.linedefs = []
        map.things = []
        map.segs = []
        map.nodes= []
        map.subsectors = []
        map.sectors = []
        map.sidedefs = []
        
        map.name = mapname
        map_index = getlump_directory_index(wad, mapname)
        if map_index == 0
            throw("Map $mapname not found.")
        end
        
        vertex_directory_entry = wad.directory[map_index + MAP_VERTEX_OFFSET]
        map_vertex_lump = getlump_data(wad, vertex_directory_entry)
        read_all_vertex!(IOBuffer(map_vertex_lump), map)
        
        linedef_directory_entry = wad.directory[map_index + MAP_LINEDEFS_OFFSET]
        map_linedef_lump = getlump_data(wad, linedef_directory_entry)
        read_all_linedef!(IOBuffer(map_linedef_lump), map)

        things_directory_entry = wad.directory[map_index + MAP_THINGS_OFFSET]
        map_thing_lump = getlump_data(wad, things_directory_entry)
        read_all_things!(IOBuffer(map_thing_lump), map)

        nodes_directory_entry = wad.directory[map_index + MAP_NODES_OFFSET]
        map_node_lump = getlump_data(wad, nodes_directory_entry)
        read_all_nodes!(IOBuffer(map_node_lump), map)

        segs_directory_entry = wad.directory[map_index + MAP_SEGS_OFFSET]
        map_segs_lump = getlump_data(wad, segs_directory_entry)
        read_all_segs!(IOBuffer(map_segs_lump), map)

        subsectors_directory_entry = wad.directory[map_index + MAP_SUBSECTORS_OFFSET]
        map_subsectors_lump = getlump_data(wad, subsectors_directory_entry)
        read_all_subsectors!(IOBuffer(map_subsectors_lump), map)

        sectors_directory_entry = wad.directory[map_index + MAP_SECTORS_OFFSET]
        map_sectors_lump = getlump_data(wad, sectors_directory_entry)
        read_all_sectors!(IOBuffer(map_sectors_lump), map)

        sidedef_directory_entry = wad.directory[map_index + MAP_SIDEDEFS_OFFSET]
        map_sidedef_lump = getlump_data(wad, sidedef_directory_entry)
        read_all_sidedefs!(IOBuffer(map_sidedef_lump), map)

        # reject_table_entry = wad.directory[map_index + MAP_REJECT_OFFSET]
        # reject_table_lump = getlump_data(wad, reject_table_entry)
        # read_reject_table!(IOBuffer(reject_table_lump), map)

        blockmap_entry = wad.directory[map_index + MAP_BLOCKMAP_OFFSET]
        blockmap_lump = getlump_data(wad, blockmap_entry)
        blockmap = read_blockmap!(IOBuffer(blockmap_lump), map)
        map.blockmap = blockmap
        return map
    end

    function get_node(map, node_id)
        return map.nodes[node_id+1]
    end

    function get_vertex(map, vertex_id)
        return map.vertexes[vertex_id+1]
    end

    function get_subsector(map, subsector_id)
        return map.subsectors[subsector_id+1]
    end

    function get_seg(map, seg_id)
        return map.segs[seg_id+1]
    end

    function get_seg_sectors(map, seg)
        seg_linedef = get_linedef(map, seg.lindef)

        if seg.direction == 1 #back
            front_sidedef = get_sidedef(map,seg_linedef.leftsidedef)
            back_sidedef = get_sidedef(map,seg_linedef.rightsidedef)
        else
            front_sidedef = get_sidedef(map,seg_linedef.rightsidedef)
            back_sidedef = get_sidedef(map,seg_linedef.leftsidedef)
        end

        if front_sidedef !== nothing
            front_sector = get_sector(map, front_sidedef.sector)
        else
            front_sector = nothing
        end
        is_two_sided = (LINE_DEF_TWO_SIDED & seg_linedef.flags) !=0
        if is_two_sided
            if back_sidedef !== nothing
                back_sector = get_sector(map, back_sidedef.sector)
            else
                back_sector = nothing
            end
        else
            back_sector = nothing
        end
        return (front_sector, back_sector)
    end

    function get_linedef_back_sector_heights(map, linedef)
        back_sidedef = get_sidedef(map, linedef.leftsidedef)
        back_sector = get_sector(map, back_sidedef.sector)
        return (back_sector.floor_height, back_sector.ceiling_height)
    end

    function get_sidedef(map, sidedef_id)
        if sidedef_id == 0xFFFF  # undefined sidedef
            return nothing
        end
        return map.sidedefs[sidedef_id+1]
    end

    function get_sector(map, sector_id)
        return map.sectors[sector_id+1]
    end

    function get_linedef(map, linedef_id)
        return map.linedefs[linedef_id+1]
    end

    function get_player(map)
        return map.things[begin]
    end

    function get_subsector_height(player, map)
        root_node_id = length(map.nodes) -1
        subsector_id = root_node_id
        while (subsector_id & SUB_SECTOR_INDENTIFIER) == 0
            node = get_node(map, subsector_id)
            is_on_back = Geometry.is_player_on_leftside(player, node)
            if is_on_back
                subsector_id = node.left_child
            else
                subsector_id = node.right_child
            end
        end
        subsector = get_subsector(map, (subsector_id) & (~SUB_SECTOR_INDENTIFIER))
        seg = get_seg(map, subsector.first_seg)
        front_sector, _ = get_seg_sectors(map, seg)
        return front_sector.floor_height, front_sector.ceiling_height
    end

    function get_blocklist_for_pos(map, x, y)
        x_origin, y_origin, bmw, bmh = get_blockmap_rectangle(map)
        in_blockmap = Collision.point_in_rectangle(x, y, x_origin, y_origin, bmw, bmh)
        if !in_blockmap
            return [] 
        end
        offset_from_x = x - x_origin
        offset_from_y = y - y_origin
        blockmap_x = Int(ceil(offset_from_x / 128))
        blockmap_y = Int(floor(offset_from_y / 128)) 

        lindefs = []
        index = (map.blockmap.header.columns * blockmap_y + blockmap_x)
        blocklist = map.blockmap.blocklists[index]
        for linedef_id in blocklist
            # if linedef_id == 0
            #     continue
            # end
            push!(lindefs, get_linedef(map, linedef_id))
        end
        return lindefs
    end

    function get_blockmap_rectangle(map)
        x_origin = map.blockmap.header.x_origin
        y_origin = map.blockmap.header.y_origin
        block_map_width = map.blockmap.header.columns * 128
        block_map_height = map.blockmap.header.rows * 128
        return (x_origin, y_origin, block_map_width, block_map_height)
    end

    function point_in_subsector(x, y, map)
        root_node_id = length(map.nodes) -1
        subsector_id = root_node_id
        while (subsector_id & SUB_SECTOR_INDENTIFIER) == 0
            node = get_node(map, subsector_id)
            is_on_back = Geometry.is_point_on_leftside(x, y, node)
            if is_on_back
                subsector_id = node.left_child
            else
                subsector_id = node.right_child
            end
        end
        subsector = get_subsector(map, (subsector_id) & (~SUB_SECTOR_INDENTIFIER))
        return subsector
    end
end