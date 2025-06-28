module Render2d
    using ..Maps
    using ..Settings
    using ..Collision
    using ..Render3d
    using SimpleDirectMediaLayer
    using SimpleDirectMediaLayer.LibSDL2

    function calculate_screenspace_offsets(player, map_scale)
        offset_x = Settings.HALF_WIDTH - trunc(Int, player.x * map_scale)
        offset_y = Settings.HALF_HEIGHT - trunc(Int, player.y * map_scale)
        if offset_x + player.x == -Settings.HALF_WIDTH
            offset_x = -offset_x
        end 
        if offset_y + player.y == -Settings.HALF_HEIGHT
            offset_y = -offset_y
        end 
       return offset_x, offset_y
    end

    function world_to_screen(x, y, offset_x, offset_y, map_scale)
        screenspace_x = trunc(Int, x*map_scale) + offset_x
        screenspace_y = trunc(Int, y*map_scale) + offset_y 
        return screenspace_x, Settings.HEIGHT - screenspace_y
    end

    function render_fov(renderer, player, x_offset, y_offset, map_scale)
        angle = -player.angle + 90
        sin_angle1 = sin(deg2rad(angle - Settings.HALF_FOV))
        cos_angle1 = cos(deg2rad(angle - Settings.HALF_FOV))
        sin_angle2 = sin(deg2rad(angle + Settings.HALF_FOV))
        cos_angle2 = cos(deg2rad(angle + Settings.HALF_FOV))
        length_of_ray = Settings.HEIGHT

        x1, y1 = world_to_screen(trunc(Int,player.x + length_of_ray * sin_angle1), trunc(Int, player.y + length_of_ray * cos_angle1), x_offset, y_offset, map_scale)
        x2, y2 = world_to_screen(trunc(Int,player.x + length_of_ray * sin_angle2), trunc(Int, player.y + length_of_ray * cos_angle2), x_offset, y_offset, map_scale)
        SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255)
        player_x, player_y = world_to_screen(trunc(Int, player.x), trunc(Int, player.y), x_offset, y_offset, map_scale)
        SDL_RenderDrawLine(renderer, player_x, player_y, x1, y1)
        SDL_RenderDrawLine(renderer,player_x, player_y, x2, y2)
    end

    function render_collisions(renderer, player, map, x_offset, y_offset, map_scale)
        linedefs = Maps.get_blocklist_for_pos(map, player.x, player.y)
        
        for line in linedefs
            p1 = Maps.get_vertex(map, line.startvertex)
            p2 = Maps.get_vertex(map, line.endvertex)
            velocity_scaled = player.velocity * 2
            velocity_cast_x =  player.x + velocity_scaled[1]
            velocity_cast_y =  player.y + velocity_scaled[2]
            SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255)
            player_x, player_y = world_to_screen(trunc(Int,player.x), trunc(Int,player.y), x_offset, y_offset, map_scale)
            velocity_x, velocity_y = world_to_screen(trunc(Int,velocity_cast_x), trunc(Int,velocity_cast_y), x_offset, y_offset, map_scale)
            SDL_RenderDrawLine(renderer,player_x,player_y, velocity_x, velocity_y)
            has_collided, intersection_x, intersection_y = Collision.line_in_line(player.x, player.y, velocity_cast_x,velocity_cast_y, p1.x, p1.y, p2.x, p2.y)
            if has_collided
                SDL_SetRenderDrawColor(renderer, 0,255, 255, 255)
                screen_intersection_x, screen_intersection_y = world_to_screen(trunc(Int,intersection_x), trunc(Int,intersection_y), x_offset, y_offset, map_scale)
                SDL_RenderDrawPoint(renderer, screen_intersection_x, screen_intersection_y)
                SDL_SetRenderDrawColor(renderer, 0, 0, 255, 255)
            else
                SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255)
            end
            screen_p1x, screen_p1y = world_to_screen(trunc(Int,p1.x), trunc(Int,p1.y), x_offset, y_offset, map_scale)
            screen_p2x, screen_p2y = world_to_screen(trunc(Int,p2.x), trunc(Int,p2.y), x_offset, y_offset, map_scale)
            SDL_RenderDrawLine(renderer, screen_p1x, screen_p1y, screen_p2x, screen_p2y)
        end
    end

    function render_vissprites(renderer, x_offset, y_offset, map_scale)
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255)
        for thing in Render3d.VISSPRITES
            remapped_x, remapped_y = world_to_screen(trunc(Int, thing.second.x), trunc(Int, thing.second.y), x_offset, y_offset, map_scale)
            if SDL_RenderDrawPoint(renderer,remapped_x, remapped_y) !=0 
                print(unsafe_string(SDL_GetError()))
            end
        end
    end

    function render_potentially_visable_seg(renderer, map, offset_x, offset_y,  map_scale)
        for seg in Render3d.SEGS_RENDERED
            render_seg(renderer, map, seg, offset_x, offset_y, map_scale)
        end
    end

    function rendermap(renderer, map, player, show_blockmap)
        map_scale = 0.2
        offset_x, offset_y = calculate_screenspace_offsets(player,map_scale)
        renderplayer(renderer, player, offset_x, offset_y, map_scale)
        render_vertexes(renderer, map,  offset_x, offset_y, map_scale)
        render_linedefs(renderer, map, offset_x, offset_y,  map_scale)
        render_collisions(renderer, player, map, offset_x, offset_y, map_scale)
        #render_vissprites(renderer, offset_x, offset_y,  map_scale)
        render_potentially_visable_seg(renderer, map, offset_x, offset_y,  map_scale)
        
        if show_blockmap
            render_block_map(renderer, map, offset_x, offset_y, map_scale)
        end
    end

    function renderplayer(renderer, player, offset_x, offset_y, map_scale)
        SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255)
        screen_x , screen_y = world_to_screen(player.x, player.y, offset_x, offset_y, map_scale)
        if SDL_RenderDrawPoint(renderer, screen_x, screen_y) !=0 
            print(unsafe_string(SDL_GetError()))
        end
        render_fov(renderer, player, offset_x, offset_y, map_scale)
    end

    function render_vertexes(renderer, map, offset_x, offset_y, map_scale)
        SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255)
        for v in map.vertexes
            screen_x, screen_y  = world_to_screen(v.x, v.y, offset_x, offset_y, map_scale)
            if SDL_RenderDrawPoint(renderer,screen_x, screen_y) !=0 
                print(unsafe_string(SDL_GetError()))
            end
        end
    end

    function render_linedefs(renderer, map, offset_x, offset_y, map_scale)
        for line in map.linedefs
            p1 = Maps.get_vertex(map, line.startvertex)
            p2 = Maps.get_vertex(map, line.endvertex)
            p1_screen_x, p1_screen_y = world_to_screen(p1.x, p1.y, offset_x, offset_y, map_scale)
            p2_screen_x, p2_screen_y = world_to_screen(p2.x, p2.y, offset_x, offset_y, map_scale)
            SDL_RenderDrawLine(renderer, p1_screen_x, p1_screen_y, p2_screen_x, p2_screen_y)
        end
    end

    function render_seg(renderer, map, seg, x_offset, y_offset, map_scale)
        v1 = Maps.get_vertex(map, seg.start_vertex)
        v2 = Maps.get_vertex(map, seg.end_vertex)
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255)
        v1x, v1y = world_to_screen(trunc(Int, v1.x), trunc(Int, v1.y), x_offset, y_offset, map_scale)
        v2x, v2y = world_to_screen(trunc(Int, v2.x), trunc(Int, v2.y), x_offset, y_offset, map_scale)
        SDL_RenderDrawLine(renderer, v1x, v1y, v2x, v2y)
    end

    function render_block_map(renderer, map, x_offset, y_offset, map_scale)
        x_origin, y_origin, bmw, bmh = Maps.get_blockmap_rectangle(map)
        SDL_SetRenderDrawColor(renderer, 128, 128, 128, 128)

        x_end, y_end = world_to_screen(x_origin+bmw,y_origin-bmh, x_offset, y_offset, map_scale)
        
        for (i,row) in enumerate(0:map.blockmap.header.rows)
            y = y_origin + (i * 128)
            _ , rm_y = world_to_screen(0, y, x_offset, y_offset, map_scale)
            SDL_RenderDrawLine(renderer,0, rm_y, x_end, rm_y)
        end

        for (i,column) in enumerate(0:map.blockmap.header.columns)
            x = x_origin + (i * 128)
            rm_x , _ = world_to_screen(x, 0, x_offset, y_offset, map_scale)
            SDL_RenderDrawLine(renderer,rm_x, 0, rm_x, y_end)
        end
    end

    function get_random_color()
        return (rand(100:254), rand(100:254), rand(100:254), 255)
    end

end