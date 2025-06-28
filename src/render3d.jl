

module Render3d

    using SimpleDirectMediaLayer
    using SimpleDirectMediaLayer.LibSDL2
    using LinearAlgebra
    using Random
    
    using ..Assets
    using ..Geometry: init_tables, 
    check_bbox, 
    scale_from_global_angle, 
    is_player_on_leftside, 
    point_to_angle, 
    norm, 
    angle_to_x,
    X_TO_ANGLE_TABLE

    using ..Maps
    using ..Settings
    using ..Colors
    using ..SDLUtils: xy_to_surface_index
    using ..Bsp

    export init_renderer, 
    init_new_frame, 
    render_bsp_node

    
    SCREEN_RANGE::Set{Int32} = Set()
    IS_TRAVERSE_BSP::Bool = true 
    UPPER_CLIP::Vector{Int32} = []
    LOWER_CLIP::Vector{Int32} = []
    
    global SEGS_RENDERED::Vector{Maps.Seg} = []

    struct VisSprite 
        x1::Int32
        x2::Int32
        gx::Int32
        gy::Int32
        gz::Int32
        gzt::Int32
        startfrac::Int32
        scale::Int32
        xisscale::Bool
        texturemid::Assets.Graphic
        patch::Assets.Graphic
        #color_map TODO SOON
        #brightmap TODO SOON
        mobjflags::Int32
    end

    global VISSPRITES::Dict{UInt64, Maps.Thing} = Dict()

    struct DrawSeg
        x1::Int32
        x2::Int32
        scale1::Int32
        scale2::Int32
        scalestep::Int32
        sillhouette::Int32
        bsilheight::Int32
        tsilheight::Int32
    end

    struct SpriteFrame
        rotate::Int32
        frame::Assets.Graphic
        flip::Base.ByteArray
    end

    struct SpriteDef
        numframes::Int32
        frames::Vector{SpriteFrame}
    end

    function init_renderer()
        init_tables()
    end

    function init_new_frame()
        global IS_TRAVERSE_BSP = true
        init_screen_range_for_frame()
        init_floor_ceil_clip_height()
        empty!(VISSPRITES)
        empty!(SEGS_RENDERED)
    end

    function init_floor_ceil_clip_height()
        global UPPER_CLIP = [-1 for _ in 1:Settings.WIDTH]
        global LOWER_CLIP = [Settings.HEIGHT for _ in 1:Settings.WIDTH]
    end
    function init_screen_range_for_frame()
        global SCREEN_RANGE = Set(1:Settings.WIDTH)
    end

    function render_player_view(renderer, player, map, node_id, asset_data)
        render_bsp_node(renderer, player, map, node_id, asset_data)
        draw_masked(renderer, player, map, asset_data)
    end

    function draw_masked(renderer, player, map, asset_data)
        # sort vissprites drawing order. For now were just getting one. 
        for thing in VISSPRITES
            sprite = Assets.doom_type_to_sprite(thing.second.type, asset_data)
            if isnothing(sprite) # case for sprites we have not added to doom sprite map yet.
                continue
            end
            draw_sprite(renderer, player, map, sprite, asset_data)
        end
    end

    function draw_sprite(renderer, player, map, sprite, asset_data)
        spot = SDL_Rect(0,0,Settings.WIDTH, Settings.HEIGHT)
        SDL_BlitSurface(sprite, C_NULL, renderer,Ref(spot))
    end
    
    function render_bsp_node(renderer, player, map, node_id, asset_data)
        if IS_TRAVERSE_BSP == true
            if (node_id & Maps.SUB_SECTOR_INDENTIFIER) !=0
                subsector_id = (node_id) & (~Maps.SUB_SECTOR_INDENTIFIER)
                render_subsector(renderer, player, map, subsector_id, asset_data)
                return nothing
            end
            node = Maps.get_node(map, node_id)
            is_on_leftside = is_player_on_leftside(player, node)

            if is_on_leftside
                render_bsp_node(renderer, player, map, node.left_child, asset_data)
                if check_bbox(player, node.right_bounding_box)
                    render_bsp_node(renderer, player, map, node.right_child, asset_data)
                end
                
            else
                render_bsp_node(renderer, player, map, node.right_child, asset_data)
                if check_bbox(player, node.left_bounding_box)
                    render_bsp_node(renderer, player, map, node.left_child, asset_data)
                end
            end
        end
    end

    function render_subsector(renderer, player, map, subsector_id, asset_data)
        subsector = Maps.get_subsector(map, subsector_id)
        seg = get_seg(map, subsector.first_seg)
        for thing in subsector.things_list
            if haskey(VISSPRITES, objectid(thing))
                continue
            end
            sprite_in_player_fov = is_point_in_fov(player, thing.second.x,  thing.second.y)
            if sprite_in_player_fov
                VISSPRITES[objectid(thing)] = thing.second
            end
        end
        for i in 0:subsector.seg_count-1
            seg = Maps.get_seg(map, subsector.first_seg + i)
            Maps.get_seg_sectors(map, seg)
            start_vertex = Maps.get_vertex(map, seg.start_vertex)
            end_vertex = Maps.get_vertex(map, seg.end_vertex)
            should_render, x1, x2, angle = should_add_segment_to_fov(player,[start_vertex.x, start_vertex.y], [end_vertex.x, end_vertex.y])
            if should_render
                push!(SEGS_RENDERED, seg) # used later for sprite clipping.
                #draw_seg(renderer, map, seg)
                classify_segment(renderer, player, map, seg, x1, x2, angle, asset_data)
                #SDL_RenderPresent(renderer)
                
            end
        end
    end

    function is_point_in_fov(player, x, y)
        angle = point_to_angle(player, [x,y])
        angle -= player.angle
        angle_to_x(angle)
        span = norm(angle + Settings.HALF_FOV)
        if span > Settings.FOV
            return false
        end
        return true
    end

    function classify_segment(renderer, player, map, seg, x1, x2, angle, asset_data)
        if x1 == x2
            return nothing
        end

        front_sector, back_sector = Maps.get_seg_sectors(map, seg)

        # this means its a solid wall
        if back_sector === nothing
            clip_solid_walls(renderer, player, map, seg, x1, x2, angle, asset_data)
            return nothing
        end

        #this means its a wall with a window
        if front_sector.ceiling_height != back_sector.ceiling_height || front_sector.floor_height != back_sector.floor_height
            clip_portal_walls(renderer, player, map, seg, x1, x2, angle, asset_data)
            return nothing
        end

        linedef = Maps.get_linedef(map, seg.lindef)
        front_sidedef = Maps.get_sidedef(map, linedef.rightsidedef)
        
        # reject empty lines that are used as triggers or events.
        # identical floor and ceiling on both sidedefs
        # identical light levels on both sides and no middle texture.
        if back_sector.ceiling_texture == front_sector.ceiling_texture && 
            back_sector.floor_texture == front_sector.floor_texture &&
            back_sector.light_level == front_sector.light_level &&
            front_sidedef.middle_texture == "-"
            return nothing
        end

        # borders with different light levels and textures
        clip_portal_walls(renderer, player, map, seg, x1, x2, angle, asset_data)
    end

    function draw_portal_wall_range(renderer, player, map, seg, x1, x2, rw_angle1, asset_data)
        global UPPER_CLIP
        global LOWER_CLIP
        front_sector, back_sector = Maps.get_seg_sectors(map, seg)
        
        line_def = Maps.get_linedef(map, seg.lindef)
        side_def = Maps.get_sidedef(map, line_def.rightsidedef)
        back_side_def = Maps.get_sidedef(map, line_def.leftsidedef)
        is_two_sided = (Maps.LINE_DEF_TWO_SIDED & line_def.flags) !=0
        if is_two_sided
            if side_def.upper_texture == "-"
                side_def.upper_texture = back_side_def.upper_texture
            end
            if side_def.lower_texture == "-"
                side_def.lower_texture = back_side_def.lower_texture
            end
        end

        # textures
        upper_wall_texture = side_def.upper_texture
        lower_wall_texture = side_def.lower_texture
        tex_ceil_id = front_sector.ceiling_texture
        tex_floor_id = front_sector.floor_texture
        light_level = front_sector.light_level

        world_front_z1 = front_sector.ceiling_height - player.eye_height
        world_back_z1 = back_sector.ceiling_height - player.eye_height
        world_front_z2 = front_sector.floor_height - player.eye_height
        world_back_z2 = back_sector.floor_height - player.eye_height

        # SKY HACK TODO
        if front_sector.ceiling_texture == back_sector.ceiling_texture == "F_SKY1"
            world_front_z1 = world_back_z1
        end

        if world_front_z1 != world_back_z1 || front_sector.light_level != back_sector.light_level || front_sector.ceiling_texture != back_sector.ceiling_texture
            b_draw_upper_wall = side_def.upper_texture != "-" && world_back_z1 < world_front_z1
            b_draw_ceil = world_front_z1 >= 0 || front_sector.ceiling_texture == "F_SKY1"
        else
            b_draw_upper_wall = false
            b_draw_ceil = false
        end
       
        if world_front_z2 != world_back_z2 || front_sector.floor_texture != back_sector.floor_texture || front_sector.light_level != back_sector.light_level
            

            b_draw_lower_wall = side_def.lower_texture != "-" && world_back_z2 > world_front_z2
            b_draw_floor = world_front_z2 <=0
        else
            b_draw_lower_wall = false
            b_draw_floor = false
        end

        if !b_draw_upper_wall && !b_draw_ceil && !b_draw_lower_wall && !b_draw_floor
            return nothing
        end
       
        rw_normal_angle = seg.angle + 90
        offset_angle = rw_normal_angle - rw_angle1
        start_vertex = Maps.get_vertex(map, seg.start_vertex)
        hypotenuse = LinearAlgebra.norm([player.x, player.y] - [start_vertex.x, start_vertex.y])
        rw_distance = hypotenuse * cos(deg2rad(offset_angle))

        rw_scale::Float64 = scale_from_global_angle(x1, player, rw_normal_angle, rw_distance)
        if x2 > x1
            scale2::Float64 = scale_from_global_angle(x2, player, rw_normal_angle, rw_distance)
            rw_scale_step = (scale2 - rw_scale) / (x2 - x1)
        else
            rw_scale_step = 0
        end

        # determine how the wall textures are vertically aligned
        if b_draw_upper_wall
            upper_wall_texture = Assets.get_texture(asset_data, side_def.upper_texture)

            if (line_def.flags & Maps.LINE_DEF_DONT_PEG_TOP) !=0
                upper_tex_alt = world_front_z1
            else
                v_top = back_sector.ceiling_height + unsafe_load(upper_wall_texture.surface).h
                upper_tex_alt = v_top - player.eye_height
            end
            upper_tex_alt += side_def.y_offset
        end

        if b_draw_lower_wall
            lower_wall_texture = Assets.get_texture(asset_data, side_def.lower_texture)

            if (line_def.flags & Maps.LINE_DEF_DONT_PEG_BOTTOM) !=0
                lower_tex_alt = world_front_z1
            else
                lower_tex_alt = world_back_z2
            end
            lower_tex_alt += side_def.y_offset
        end

        # determine how the wall textures are horizontally aligned
        seg_textured = b_draw_upper_wall || b_draw_lower_wall
        if seg_textured
            rw_offset = hypotenuse * sin(deg2rad(offset_angle))
            rw_offset += seg.offset + side_def.x_offset
            #
            rw_center_angle = rw_normal_angle - player.angle
        end

        wall_y1 = Settings.HALF_HEIGHT - world_front_z1 * rw_scale
        wall_y1_step = -rw_scale_step * world_front_z1
        wall_y2 = Settings.HALF_HEIGHT - world_front_z2 * rw_scale
        wall_y2_step = -rw_scale_step * world_front_z2

        if b_draw_upper_wall
            if world_back_z1 > world_back_z2
                portal_y1 = Settings.HALF_HEIGHT - world_back_z1 * rw_scale
                portal_y1_step = -rw_scale_step * world_back_z1
            else
                portal_y1 = wall_y2
                portal_y1_step = wall_y2_step
            end
        end

        if b_draw_lower_wall
            if world_back_z2 < world_front_z1
                portal_y2 = Settings.HALF_HEIGHT - world_back_z2 * rw_scale
                portal_y2_step = -rw_scale_step * world_back_z2
            else
                portal_y2 = wall_y1
                portal_y2_step = wall_y1_step
            end
        end

        for x in x1:x2
            draw_wall_y1 = wall_y1 -1
            draw_wall_y2 = wall_y2

            if seg_textured
                angle = rw_center_angle - X_TO_ANGLE_TABLE[x]
                texture_column = rw_distance * tan(deg2rad(angle)) - rw_offset
                inv_scale = 1.0 / rw_scale
            end

            if b_draw_upper_wall
                draw_upper_wall_y1 = wall_y1 -1
                draw_upper_wall_y2 = portal_y1
                
                if b_draw_ceil
                    cy1 = UPPER_CLIP[x] + 1
                    cy2 = trunc(Int, min(draw_wall_y1 -1, LOWER_CLIP[x] - 1))
                    draw_flat(renderer, x, cy1, cy2, front_sector.ceiling_texture, front_sector.light_level, asset_data, player, world_front_z1)
                end

                wy1 = trunc(Int, max(draw_upper_wall_y1, UPPER_CLIP[x] + 1))
                wy2 = trunc(Int, min(draw_upper_wall_y2, LOWER_CLIP[x] - 1))
                draw_wall_column(renderer, upper_wall_texture, texture_column, x, wy1, wy2, upper_tex_alt, inv_scale, light_level /255.0)

                if UPPER_CLIP[x] < wy2
                    UPPER_CLIP[x] = wy2
                end

                portal_y1 += portal_y1_step
            end

            if b_draw_ceil
                cy1 = UPPER_CLIP[x] + 1
                cy2 = trunc(Int, min(draw_wall_y1 - 1, LOWER_CLIP[x] - 1))
                draw_flat(renderer, x, cy1, cy2, front_sector.ceiling_texture, front_sector.light_level, asset_data, player, world_front_z1)

                if UPPER_CLIP[x] < cy2
                    UPPER_CLIP[x] = cy2
                end
            end

            if b_draw_lower_wall
                if b_draw_floor
                    fy1 = trunc(Int, max(draw_wall_y2 + 1, UPPER_CLIP[x] + 1))
                    fy2 = LOWER_CLIP[x] - 1
                    draw_flat(renderer, x, fy1, fy2, front_sector.floor_texture, front_sector.light_level, asset_data, player, world_front_z2)
                end

                draw_lower_wall_y1 = portal_y2 - 1
                draw_lower_wall_y2 = wall_y2

                wy1 = trunc(Int, max(draw_lower_wall_y1, UPPER_CLIP[x] +1))
                wy2 = trunc(Int, min(draw_lower_wall_y2, LOWER_CLIP[x] -1))
                draw_wall_column(renderer, lower_wall_texture, texture_column, x, wy1, wy2, lower_tex_alt, inv_scale, light_level /255.0)

                if LOWER_CLIP[x] > wy1
                    LOWER_CLIP[x] = wy1
                end
                portal_y2 += portal_y2_step
            end

            if b_draw_floor
                fy1 = trunc(Int, max(draw_wall_y2 +1, UPPER_CLIP[x] + 1))
                fy2 = LOWER_CLIP[x] - 1
                draw_flat(renderer, x, fy1, fy2, front_sector.floor_texture, front_sector.light_level, asset_data, player, world_front_z2)

                if LOWER_CLIP[x] > draw_wall_y2 + 1
                    LOWER_CLIP[x] = fy1
                end
            end

            rw_scale += rw_scale_step
            wall_y1 += wall_y1_step
            wall_y2 += wall_y2_step
        end
    end

    function draw_solid_wall_range(renderer, player, map, seg, x1, x2, rw_angle1, asset_data)
        front_sector, back_sector = Maps.get_seg_sectors(map, seg)
        
        line_def = Maps.get_linedef(map, seg.lindef)
        side_def = Maps.get_sidedef(map, line_def.rightsidedef)
        
        wall_texture_id = side_def.middle_texture
        ceil_texture = front_sector.ceiling_texture
        floor_texture = front_sector.floor_texture
        light_level = front_sector.light_level 
       
        world_front_z1 = front_sector.ceiling_height - player.eye_height
        world_front_z2 = front_sector.floor_height - player.eye_height

        b_draw_wall = side_def.middle_texture != "-"
        b_draw_ceil = world_front_z1 > 0 || ceil_texture == "F_SKY1" 
        b_draw_floor = world_front_z2 < 0

        rw_normal_angle = seg.angle + 90
        offset_angle = rw_normal_angle - rw_angle1
       
        start_vertex = Maps.get_vertex(map, seg.start_vertex)
        hypotenuse = LinearAlgebra.norm([player.x, player.y] - [start_vertex.x, start_vertex.y])

        rw_distance = hypotenuse * cos(deg2rad(offset_angle))
        rw_scale1::Float64 = scale_from_global_angle(x1, player, rw_normal_angle, rw_distance)
        if isapprox(offset_angle % 360, 90, atol=1)
            rw_scale1 *= 0.01
        end
        if x1 < x2
            scale2::Float64 = scale_from_global_angle(x2, player, rw_normal_angle, rw_distance)
            rw_scale_step = (scale2 - rw_scale1) / (x2 - x1)
        else
            rw_scale_step = 0
        end

        # textures
        wall_texture = Assets.get_texture(asset_data, wall_texture_id)
        if (line_def.flags & Maps.LINE_DEF_DONT_PEG_BOTTOM) !=0
            v_top = front_sector.floor_height + unsafe_load(wall_texture.surface).h
            middle_tex_alt = v_top - player.eye_height
        else
            middle_tex_alt = world_front_z1
        end
        middle_tex_alt += side_def.y_offset

        # determine how the wall textures are horizontally aligned
        rw_offset = hypotenuse * sin(deg2rad(offset_angle))
        rw_offset += seg.offset + side_def.x_offset
        #
        rw_center_angle = rw_normal_angle - player.angle
        #end

        wall_y1 = Settings.HALF_HEIGHT - world_front_z1 * rw_scale1
        wall_y1_step = -rw_scale_step * world_front_z1

        wall_y2 = Settings.HALF_HEIGHT - world_front_z2 * rw_scale1
        wall_y2_step = -rw_scale_step * world_front_z2

        for x in x1:x2
            draw_wall_y1 = wall_y1 -1
            draw_wall_y2 = wall_y2

            if b_draw_ceil
                cy1 = UPPER_CLIP[x] + 1
                cy2 = trunc(Int, min(draw_wall_y1 -1, LOWER_CLIP[x] -1))
                draw_flat(renderer, x, cy1, cy2, ceil_texture, light_level, asset_data, player, world_front_z1)
            end

            if b_draw_wall
                wy1 = trunc(Int, max(draw_wall_y1, UPPER_CLIP[x] + 1))
                wy2 = trunc(Int, min(draw_wall_y2, LOWER_CLIP[x] - 1))

                if wy1 < wy2
                    angle = rw_center_angle - X_TO_ANGLE_TABLE[x]
                    rads = deg2rad(angle)
                    tangent = tan(rads)
                    texture_column = rw_distance * tangent - rw_offset
                    inv_scale = 1.0 / rw_scale1
                    draw_wall_column(renderer, wall_texture, texture_column, x, wy1, wy2, middle_tex_alt, inv_scale, light_level /255.0)
                end
            end

            if b_draw_floor
                fy1 = trunc(Int, max(draw_wall_y2 + 1, UPPER_CLIP[x] + 1))
                fy2 = LOWER_CLIP[x] - 1
                draw_flat(renderer, x, fy1, fy2, floor_texture, light_level, asset_data, player, world_front_z2)
            end

            rw_scale1 += rw_scale_step
            wall_y1 += wall_y1_step
            wall_y2 += wall_y2_step
        end
    end

    function clip_portal_walls(renderer, player, map, seg, x_start, x_end, angle, asset_data)
        global IS_TRAVERSE_BSP
        current_wall = Set(x_start:x_end-1)
        intersection = intersect(current_wall, SCREEN_RANGE)
        if length(intersection) > 0
            if length(intersection) == length(current_wall)
                draw_portal_wall_range(renderer, player, map, seg,x_start, x_end -1, angle, asset_data)
            else
                arr = sort(collect(intersection))
                x = arr[begin] 
                for vals in zip(arr, arr[2:end])
                    x1, x2 = vals
                    if x2 - x1 > 1
                        draw_portal_wall_range(renderer, player, map, seg, x, x1, angle, asset_data)
                        x = x2
                    end
                end
                draw_portal_wall_range(renderer, player, map, seg, x, arr[end], angle, asset_data)
            end
        end
    end

    function clip_solid_walls(renderer, player, map, seg, x_start, x_end, angle, asset_data)
        global SCREEN_RANGE
        global IS_TRAVERSE_BSP
        if length(SCREEN_RANGE) != 1
            current_wall = Set(x_start:x_end-1)
            intersection = intersect(current_wall, SCREEN_RANGE)
            if length(intersection) > 0
                if length(intersection) == length(current_wall)
                    draw_solid_wall_range(renderer, player, map, seg, x_start, x_end-1, angle, asset_data)
                else
                    arr = sort(collect(intersection))
                    x, x2 = arr[begin], arr[end]
                    for vals in zip(arr, arr[2:end])
                        x1, x2 = vals
                        if x2 - x1 > 1
                            draw_solid_wall_range(renderer, player, map, seg, x, x1, angle, asset_data)
                            x = x2
                        end
                    end
                    
                    draw_solid_wall_range(renderer, player, map, seg, x, x2, angle, asset_data)
                end
                for item in intersection
                    delete!(SCREEN_RANGE, item)
                end
            end
        else
            global IS_TRAVERSE_BSP = false
        end

    end

    function draw_wall_column(renderer::Ptr{SDL_Surface}, tex, tex_col, x, y1, y2, tex_alt, inv_scale, light_level)
        de_ref_ptr_to_surface = unsafe_load(renderer)
        casted = Base.unsafe_convert(Ptr{UInt32}, de_ref_ptr_to_surface.pixels)
        text_de_ref = unsafe_load(tex.surface)
        text_casted = Base.unsafe_convert(Ptr{UInt32}, text_de_ref.pixels)
        width = text_de_ref.w
        height = text_de_ref.h

        if y1 < y2
            tex_w, tex_h = width, height
            tex_col = trunc(Int,tex_col) % tex_w
            tex_col = norm(tex_col, width)
            tex_y = tex_alt + (y1 - Settings.HALF_HEIGHT +2) * inv_scale
            for iy in y1:y2
                normalized_tex_y = trunc(Int,tex_y) % tex_h
                if normalized_tex_y == 0 # TODO HACK!
                    normalized_tex_y = 1
                end
                normalized_tex_y = norm(normalized_tex_y, height)
                texture_index = xy_to_surface_index(tex_col, normalized_tex_y, width)
                color = unsafe_load(text_casted, trunc(Int,texture_index))
                r,g,b,a = Colors.unpack(color)
                color =Colors.packRGB888((trunc(Int64,r*light_level),trunc(Int64,g*light_level),trunc(Int64,b*light_level),255))
                screen_index = xy_to_surface_index(x, iy, Settings.WIDTH)
                unsafe_store!(casted, color, screen_index)
                #SDL_UpdateWindowSurface(Simulacra.WINDOW)
                #SDL_Delay(1)
                tex_y += inv_scale
            end
        end
    end

    function draw_flat(renderer::Ptr{SDL_Surface}, x, y1, y2, texture, light, asset_data, player, world_z)
        if y1 < y2
            if texture == "F_SKY1" #hack TODO
                sky_texture = Assets.get_patch(asset_data, "SKY1") # for some dumb reason doom1 is a patch and doom 2 is a texture?
                if isnothing(sky_texture)
                    sky_texture = Assets.get_texture(asset_data, "SKY1")
                end
                tex_column = 2.2 * (player.angle + X_TO_ANGLE_TABLE[x])
                sky_inv_scale = 160 / Settings.HEIGHT
                sky_tex_alt = 100
                draw_wall_column(renderer, sky_texture, tex_column, x, y1, y2, sky_tex_alt, sky_inv_scale, 1)
            else
                text = Assets.get_texture(asset_data, texture)
                draw_flat_col(renderer, text, x, y1, y2, light/255.0, world_z, player.angle, player.x, player.y)
            end
        end
    end

    function draw_flat_col(renderer, flat_tex, x, y1, y2, light_level, world_z, player_angle, player_x, player_y)
        de_ref_ptr_to_surface = unsafe_load(renderer)
        casted = Base.unsafe_convert(Ptr{UInt32}, de_ref_ptr_to_surface.pixels)
        text_de_ref = unsafe_load(flat_tex.surface)
        text_casted = Base.unsafe_convert(Ptr{UInt32}, text_de_ref.pixels)
        width = text_de_ref.w

        player_dir_x = cos(deg2rad(player_angle))
        player_dir_y = sin(deg2rad(player_angle))

        if y1 == 0
            y1 == 1
        end
        for iy in y1:y2
            if Settings.HALF_HEIGHT - iy == 0
                divisor = 1
            else
                divisor = Settings.HALF_HEIGHT - iy
            end
            z = Settings.HALF_WIDTH * world_z / divisor
            px = player_dir_x * z + player_x
            py = player_dir_y * z + player_y
            left_x = -player_dir_y * z + px
            left_y = player_dir_x * z + py
            right_x = player_dir_y * z + px
            right_y = -player_dir_x * z + py

            dx = (right_x - left_x) / Settings.WIDTH
            dy = (right_y - left_y) / Settings.WIDTH
            
            tx = trunc(Int, left_x + dx * x) & 63
            ty = trunc(Int, left_y + dy * x) & 63
        
            if ty == 0
                ty = 1
            end
            texture_index = xy_to_surface_index(tx, ty, width)
            color = unsafe_load(text_casted, trunc(Int,texture_index))
            r,g,b,a = Colors.unpack(color)
            color =Colors.packRGB888((trunc(Int64,r*light_level),trunc(Int64,g*light_level),trunc(Int64,b*light_level),255))
            screen_index = xy_to_surface_index(x, iy, Settings.WIDTH)
            unsafe_store!(casted, color, screen_index)
            #SDL_UpdateWindowSurface(Simulacra.WINDOW)
            #SDL_Delay(1)
        end
    end

    function should_add_segment_to_fov(player, vertex1, vertex2)
        angle1 = point_to_angle(player, vertex1)
        angle2 = point_to_angle(player, vertex2)

        span = norm(angle1 - angle2)
        if span >= 180 # backside cull
            return false, nothing, nothing, nothing
        end

        rw_angle1 = angle1
        angle1 -= player.angle
        angle2 -= player.angle

        span1 = norm(angle1 + Settings.HALF_FOV)
        if span1 > Settings.FOV
            if span1 >= span + Settings.FOV
                return false, nothing, nothing, nothing
            end
            #clip
            angle1 = Settings.HALF_FOV
        end
        span2 = norm(Settings.HALF_FOV - angle2)
        if span2 > Settings.FOV
            if span2 >= span + Settings.FOV
                return false, nothing, nothing, nothing
            end
            angle2 = -Settings.HALF_FOV
        end
        x1 = angle_to_x(angle1)
        x2 = angle_to_x(angle2)
        return (true, x1, x2, rw_angle1) # fix this tuple mess
    end
end