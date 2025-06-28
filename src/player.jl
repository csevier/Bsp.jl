module Players
    using SimpleDirectMediaLayer
    using SimpleDirectMediaLayer.LibSDL2
    using LinearAlgebra
    using ..Maps: get_subsector_height, get_blocklist_for_pos, get_vertex, get_linedef_back_sector_heights
    using ..Settings
    using ..Geometry
    using ..Collision
    export Player, update!

    const DIAG_MOVE_CORRECTION::Float64 = 1/ sqrt(2)

    mutable struct Player 
        x::Float32
        y::Float32
        angle::Float32
        height::Int16
        eye_height::Int16
        radius::Int16
        velocity::Vector{Float32}
    end

    function is_moving(player)
        return abs(LinearAlgebra.norm(player.velocity)) > 0
    end

    function cap_velocity(player, input_velocity)
        if abs(LinearAlgebra.norm(player.velocity)) > 20
            return
        else
            player.velocity += input_velocity 
        end
    end

    function apply_friction(player)
        friction = 0.9
        current_velocity = player.velocity
        current_velocity_scaled = current_velocity * friction
        player.velocity[1] = current_velocity_scaled[1]
        player.velocity[2] = current_velocity_scaled[2]
        if abs(LinearAlgebra.norm(player.velocity)) < 0.3 # stop it from going to infinity
            player.velocity = [0,0]
        end
    end

    function adjust_heights(player, sector_floor_height)
        if sector_floor_height < player.height - 2
            player.height -= 10
        elseif sector_floor_height > player.height
            player.height += 4
        else
            player.height = sector_floor_height  
        end
        player.eye_height = player.height + 41
        head_bob(player)
    end

    function update!(player, map, dt)
        velocity_from_input, angle = handle_input(player, dt)
        cap_velocity(player, velocity_from_input)
        apply_friction(player)
        sector_floor_height, sector_ceiling_height = get_subsector_height(player, map)
        adjust_heights(player, sector_floor_height)

        player.angle -= angle
        if try_move(player, map, sector_floor_height, sector_ceiling_height)
            player.x += player.velocity[1]  
            player.y += player.velocity[2]
        else
            player.velocity = [0,0]# this will eventually shift the velocity into the wall direction
        end
    end

    function try_move(player, map, sector_floor_height, sector_ceiling_height)
        if Settings.NO_CLIP
            return true
        end
        return collide(player, map, sector_floor_height, sector_ceiling_height)
    end

    function collide(player, map, current_sector_floor_height, current_sector_ceiling_height)
        linedefs = get_blocklist_for_pos(map, player.x, player.y)
        for (i, linedef) in enumerate(linedefs)
            start = get_vertex(map, linedef.startvertex)
            end_point =  get_vertex(map, linedef.endvertex)
            velocity_scaled = player.velocity * 2
            velocity_cast_x =  player.x + velocity_scaled[1]
            velocity_cast_y =  player.y + velocity_scaled[2]
            has_collided, intersection_x, intersection_y = Collision.line_in_line(player.x, player.y,velocity_cast_x,velocity_cast_y, start.x, start.y, end_point.x, end_point.y)
            if has_collided
                if linedef.leftsidedef == 65535
                    return false
                end
                back_floor_height, back_ceiling_height = get_linedef_back_sector_heights(map,linedef)
                if current_sector_floor_height > back_floor_height
                    continue
                end
                if back_floor_height - current_sector_floor_height >= 24 #step to high
                    return false
                elseif back_ceiling_height < player.eye_height
                    return false
                end
            end
        end
        return true
    end

    function handle_input(player, dt)
        keys= SDL_GetKeyboardState(Ptr{UInt8}(C_NULL))
        keystates = unsafe_wrap(Array,keys,512)
        x = Ref{Int32}()
        y = Ref{Int32}()
        mouse_state = SDL_GetRelativeMouseState(x, y)
        delta_x = x.x 
        delta_y = y.x 
        
        velocity = [0.0,0.0]
        if keystates[UInt8(SDL_SCANCODE_W)+1] == 1
            x, y = Geometry.rotate(1, 0, Geometry.norm(player.angle))
            velocity[1] += x 
            velocity[2] += y 
        end
        if keystates[UInt8(SDL_SCANCODE_A)+1] == 1
            x, y = Geometry.rotate(0, 1, Geometry.norm(player.angle))
            velocity[1] += x 
            velocity[2] += y 
        end
        if keystates[UInt8(SDL_SCANCODE_S)+1] == 1
            x, y = Geometry.rotate(-1, 0, Geometry.norm(player.angle))
            velocity[1] += x 
            velocity[2] += y 
        end
        if keystates[UInt8(SDL_SCANCODE_D)+1] == 1
            x, y = Geometry.rotate(0, -1, Geometry.norm(player.angle))
            velocity[1] += x 
            velocity[2] += y 
        end
        if Settings.ONE_HANDED_MODE
            x, y = Geometry.rotate(-1, 0, Geometry.norm(player.angle))
            velocity[1] += x * delta_y 
            velocity[2] += y * delta_y
        end
        LinearAlgebra.normalize!(velocity)
        if isnan(velocity[1])
            velocity[1] = 0.0
        end
        if isnan(velocity[2])
            velocity[2] = 0.0
        end
        velocity = velocity * dt * Settings.PLAYER_SPEED
        angle = Settings.PLAYER_ROT_SPEED * delta_x * dt
        return velocity, angle
    end

    function head_bob(player)
        if is_moving(player)
            diff = sin( SDL_GetTicks()/100)*6
            player.eye_height += trunc(Int, diff) # we dont actually want the player moving htought, TODO
        end
    end
end