module Assets
    using SimpleDirectMediaLayer
    using SimpleDirectMediaLayer.LibSDL2

    using ..Wad
    using ..Colors
    using ..SDLUtils: write_color_to_surface, create_surface, get_matrix_from_surface
    
    export AssetData, 
    read_asset_data, 
    read_all_palletes!, 
    read_color_pallete!, 
    get_pallete

    struct PatchColumn
        top_delta::UInt8
        length::UInt8
        padding_pre:: UInt8
        data::Vector{UInt8}
        padding_post::UInt8
    end

    struct PatchHeader
        width::UInt16
        height::UInt16
        left_offset::Int16
        top_offset::Int16
        column_offsets::Vector{UInt32}
    end

    mutable struct Patch
        header::PatchHeader
        columns::Vector{PatchColumn}
    end

    mutable struct PatchMap
        x_offset::Int16
        y_offset::Int16
        patch_name_index::Int16
        step_dir::Int16
        color_map::Int16
    end

    mutable struct TextureHeader
        texture_count::Int32
        texture_data_offset::Vector{Int32}
    end

    mutable struct TextureMap
        name::String
        flags::UInt32
        width::Int16
        height::Int16
        column_dir::UInt32
        patch_count::UInt16
        patch_maps::Vector{PatchMap}
    end

    mutable struct Flat
        data::Vector{UInt8} # its the id of the color in the doom pallete
    end

    mutable struct Graphic
        surface::Ptr{SDL_Surface} # for blitting
        framebuffer::Matrix # for columns
    end

    mutable struct AssetData
        all_palletes::Vector{Vector{Tuple{UInt8,UInt8,UInt8}}}
        patch_names::Vector{String} # from PNAMES Lump
        sprites::Dict{String, Graphic}
        patches::Dict{String, Graphic}
        textures::Dict{String, Graphic}
    end

    function read_asset_data!(wad::WadData)
        asset_data = AssetData([],[],Dict{String, Graphic}(), Dict{String, Graphic}(), Dict{String, Graphic}()) # TODO fix this with constructors
        read_all_palletes!(wad, asset_data)
        read_all_sprites!(wad, asset_data)
        read_all_texture_patches!(wad, asset_data)
        read_all_texture_maps!(wad, asset_data)
        read_all_flats!(wad, asset_data)
        return asset_data
    end

    function overwrite_asset_data!(wad::WadData, asset_data)
        read_all_palletes!(wad, asset_data)
        read_all_sprites!(wad, asset_data)
        read_all_texture_patches!(wad, asset_data)
        read_all_texture_maps!(wad, asset_data)
        read_all_flats!(wad, asset_data)
    end

    function read_all_sprites!(wad, asset_data)
        sprite_start_index = Wad.getlump_directory_index(wad, "S_START")
        sprite_end_index = Wad.getlump_directory_index(wad, "S_END")
        if sprite_start_index == 0
            return
        end
        for index in sprite_start_index+1:sprite_end_index-1
            patch_entry = wad.directory[index]
            patch = read_patch(wad, patch_entry.name)
            surface = convert_patch_to_surface(patch, asset_data)
            matrix = convert_patch_to_matrix(patch, asset_data)
            graphic = Graphic(surface, matrix)
            asset_data.sprites[patch_entry.name] = graphic
        end
    end

    function convert_patch_to_surface(patch, asset_data)
        width = patch.header.width
        height = patch.header.height
        surf = create_surface(width, height)
        ix = 1
        for patch_column in patch.columns
            if patch_column.top_delta == 0xFF
                ix += 1
                continue
            end
            for iy in 1:patch_column.length
                pallette_color_index = patch_column.data[iy]
                r, g, b = asset_data.all_palletes[begin][pallette_color_index+1]
                pixel_x = ix
                pixel_y = iy + patch_column.top_delta -1
                write_color_to_surface(pixel_x, pixel_y, surf, (r,g,b,255))
            end
        end
        return surf
    end

    function convert_patch_to_matrix(patch, asset_data)
        width = patch.header.width
        height = patch.header.height
        matrix = zeros(UInt32, width, height)
        ix = 1
        for patch_column in patch.columns
            if patch_column.top_delta == 0xFF
                ix += 1
                continue
            end
            for iy in 1:patch_column.length
                pallette_color_index = patch_column.data[iy]
                r, g, b = asset_data.all_palletes[begin][pallette_color_index+1]
                pixel_x = ix
                pixel_y = iy + patch_column.top_delta
                matrix[pixel_x, pixel_y] = Colors.packRGB888((Int64(r), Int64(g), Int64(b), 255))
            end
        end
        return matrix
    end

    function convert_texture_map_to_surface(texture_map, asset_data)
        width = texture_map.width
        height = texture_map.height
        surf = create_surface(width, height)
        name = texture_map.name

        for patch_map in texture_map.patch_maps
            patch_name = asset_data.patch_names[patch_map.patch_name_index+1]
            patch_surf = get_patch(asset_data, patch_name).surface
        
            rect = SDL_Rect(patch_map.x_offset, patch_map.y_offset, width, height)
            SDL_BlitSurface(patch_surf, C_NULL, surf, Ref(rect))
        end
        return surf
    end

    function convert_flat_to_surface(flat, asset_data)
        width = 64
        height = 64
        surf = create_surface(width, height)
        for (i, color_pallete_index) in enumerate(flat.data)
            r, g, b = asset_data.all_palletes[begin][color_pallete_index+1]
            ix = i % 64
            iy = i ÷ 64
            write_color_to_surface(ix, iy, surf, (r,g,b,255))
        end
        return surf
    end

    function convert_flat_to_matrix(flat, asset_data)
        width = 64
        height = 64
        matrix = zeros(UInt32, width, height)
        for x in 1:width
            for y in 1:height
                color_pallete_index = flat.data[x*y]
                r, g, b = asset_data.all_palletes[begin][color_pallete_index+1]
                matrix[x, y] = Colors.packRGB888((Int(r),Int(g),Int(b),255))
            end
        end
        return matrix
    end

    function read_all_palletes!(wad, asset_data::AssetData)
        playpal_index = Wad.getlump_directory_index(wad, "PLAYPAL")
        if playpal_index == 0
            return
        end
        directory_entry = wad.directory[playpal_index]
        playpal_lump = Wad.getlump_data(wad, directory_entry)
        bytes = IOBuffer(playpal_lump)
        while !eof(bytes)
            pallete = read_color_pallete!(bytes)
            push!(asset_data.all_palletes, pallete)
        end
    end

    function read_color_pallete!(bytes::IOBuffer)
        pallete = []
        for i in 0:255
            r = read(bytes, UInt8)
            g = read(bytes, UInt8)
            b = read(bytes, UInt8)
            push!(pallete, (r,g,b))
        end
        return pallete
    end

    function get_pallete(asset_data, index)
        return asset_data.all_palletes[index]
    end

    function read_patch_header(bytes)
        width = read(bytes, UInt16)
        height = read(bytes, UInt16)
        left_offset = read(bytes, Int16)
        top_offset  = read(bytes, Int16)
        column_offsets = []
        for col in 1:width # TODO possible off by 1 bug
            column_offset = read(bytes, UInt32)
            push!(column_offsets, column_offset)
        end
        return PatchHeader(width, height, left_offset, top_offset, column_offsets)
    end

    function read_patch_columns(bytes, header)
        patch_columns = []
        for i in 1:header.width
            while true
                patch_column = read_patch_column(bytes)
                push!(patch_columns, patch_column)
                if patch_column.top_delta == 0xFF
                    break
                end
            end
        end
        return patch_columns
    end

    function read_patch_column(bytes)
        top_delta = read(bytes, UInt8)
        if top_delta != 0xFF
            length = read(bytes, UInt8)
            padding_pre  = read(bytes, UInt8)
            data = []
            for i in 1:length
                push!(data, read(bytes,UInt8))
            end
            padding_post = read(bytes, UInt8)
        else
            length = 0
            padding_pre  = 0
            data = []
            padding_post = 0
        end
        return PatchColumn(top_delta, length, padding_pre, data, padding_post)
    end

    function read_patch_from_bytes(bytes)
        header = read_patch_header(bytes)
        columns = read_patch_columns(bytes, header)
        return Patch(header, columns)
    end
    
    function read_patch(wad::WadData, patch_name)
        patch_index = Wad.getlump_directory_index(wad, patch_name)
        patch_directory_entry = wad.directory[patch_index]
        patch_bytes = getlump_data(wad, patch_directory_entry)
        patch = read_patch_from_bytes(IOBuffer(patch_bytes))
        return patch
    end

    function read_texture_header(bytes)
        texture_count = read(bytes, UInt32)
        texture_data_offset = []
        for i in 1:texture_count
            push!(texture_data_offset,read(bytes, UInt32))
        end
        return TextureHeader(texture_count, texture_data_offset)
    end

    function read_patch_map(bytes)
        x_offset = read(bytes, Int16)
        y_offset = read(bytes, Int16)
        patch_name_index = read(bytes, Int16)
        step_dir = read(bytes, Int16)
        color_map = read(bytes, Int16)
        return PatchMap(x_offset, y_offset, patch_name_index, step_dir, color_map)
    end

    function read_texture_map(bytes)
        name = strip(String(read(bytes,8)),'\0')
        flags = read(bytes, UInt32)
        width = read(bytes, UInt16)
        height = read(bytes, UInt16)
        column_dir = read(bytes, UInt32)
        patch_count = read(bytes, UInt16)
        patch_maps = []
        for i in 1:patch_count
            push!(patch_maps, read_patch_map(bytes)) # Not sure this is right TODO
        end
        return TextureMap(name, flags, width, height, column_dir, patch_count, patch_maps)
    end

    function read_all_texture_maps!(wad, asset_data)
        texture_map_index = Wad.getlump_directory_index(wad, "TEXTURE1")
        if texture_map_index != 0
            textures_directory_entry = wad.directory[texture_map_index]
            texture_bytes = getlump_data(wad, textures_directory_entry)
            texture_buffer = IOBuffer(texture_bytes)
            texture_header = read_texture_header(texture_buffer)
            for (i, offset) in enumerate(texture_header.texture_data_offset)
                seek(texture_buffer, offset)
                texture_map = read_texture_map(texture_buffer)
                try
                    
                    texture = convert_texture_map_to_surface(texture_map, asset_data)
                    matrix = get_matrix_from_surface(texture)
                    asset_data.textures[texture_map.name] = Graphic(texture, matrix)
                catch e
                     println("failed to convert texture map $(texture_map.name)")
                 end
            end
        end
       
        texture_map_index = Wad.getlump_directory_index(wad, "TEXTURE2")
        if texture_map_index != 0
            textures_directory_entry = wad.directory[texture_map_index]
            texture_bytes = getlump_data(wad, textures_directory_entry)
            texture_buffer = IOBuffer(texture_bytes)
            texture_header = read_texture_header(texture_buffer)
            for (i, offset) in enumerate(texture_header.texture_data_offset)
                seek(texture_buffer, offset)
                texture_map = read_texture_map(texture_buffer)
                try
                    
                    texture = convert_texture_map_to_surface(texture_map, asset_data)
                    matrix = get_matrix_from_surface(texture)
                    asset_data.textures[texture_map.name] = Graphic(texture, matrix)
                catch e
                     println("failed to convert texture map $(texture_map.name)")
                 end
            end
        end
    end

    function read_all_texture_patches!(wad, asset_data)
        pnames_index = Wad.getlump_directory_index(wad, "PNAMES")
        if pnames_index != 0
            pnames_directory_entry = wad.directory[pnames_index]
            pnames_bytes = getlump_data(wad, pnames_directory_entry)
            stream = IOBuffer(pnames_bytes)
            number_of_texture_patches = read(stream, UInt32)
            for i in 1:number_of_texture_patches
                name = strip(String(read(stream,8)),'\0')
                try # this is for shareware wads
                    push!(asset_data.patch_names,name)
                    patch = read_patch(wad, name)
                    surf = convert_patch_to_surface(patch, asset_data)
                    asset_data.patches[name] = Graphic(surf, zeros(1,1))
                catch e
                    println("Cannot read texture patch $name")
                end
            end
        else
            pnames_start_index = Wad.getlump_directory_index(wad, "PP_START")
            pnames_end_index = Wad.getlump_directory_index(wad, "PP_END")
            if pnames_start_index ==0
                return
            end
            println("reading PPS!")
            for index in pnames_start_index+1:pnames_end_index-1
                patch_entry = wad.directory[index]
                patch = read_patch(wad, patch_entry.name)
                surface = convert_patch_to_surface(patch, asset_data)
                matrix = convert_patch_to_matrix(patch, asset_data)
                graphic = Graphic(surface, matrix)
                asset_data.sprites[patch_entry.name] = graphic
            end
        end
    end

    function read_all_flats!(wad, asset_data)
        for i in 1:100 # max 100?
            flat_start = "F$(i)_START"
            flat_end = "F$(i)_END"
            flat_start_index = Wad.getlump_directory_index(wad, flat_start)
            if flat_start_index == 0
                continue
            end
            flat_end_index = Wad.getlump_directory_index(wad,flat_end)
            for index in flat_start_index+1:flat_end_index-1 # TODO possible off by one error
                flat_entry = wad.directory[index]
                bytes = getlump_data(wad, flat_entry)
                flat = read_flat(IOBuffer(bytes))
                flat_surface = convert_flat_to_surface(flat, asset_data)
                matrix = convert_flat_to_matrix(flat, asset_data)
                asset_data.textures[flat_entry.name] =  Graphic(flat_surface, matrix)
            end 
        end
    end

    function read_flat(bytes)
        data = []
        size = 64 * 64
        for i in 1:size
            push!(data,read(bytes, UInt8))
        end
        return Flat(data)
    end

    function get_texture(asset_data, texture_name)
        if haskey(asset_data.textures, texture_name)
            return asset_data.textures[texture_name]
        elseif haskey(asset_data.textures, uppercase(texture_name))
            return asset_data.textures[uppercase(texture_name)]
        elseif haskey(asset_data.textures, lowercase(texture_name))
            return asset_data.textures[lowercase(texture_name)]
        end
    end

    function get_patch(asset_data, patch_name)
        if haskey(asset_data.patches, patch_name)
            return asset_data.patches[patch_name]
        elseif haskey(asset_data.patches, uppercase(patch_name))
            return asset_data.patches[uppercase(patch_name)]
        elseif haskey(asset_data.patches, lowercase(patch_name))
            return asset_data.patches[lowercase(patch_name)]
        end
    end

    function doom_type_to_sprite(thing_type, asset_data)
        if thing_type == 2035
            return asset_data.sprites["BAR1A0"].surface
        end
    end
end