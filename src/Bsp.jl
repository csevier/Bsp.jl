module Bsp
    using SimpleDirectMediaLayer
    using SimpleDirectMediaLayer.LibSDL2
    using Dates
    using Profile
    include("settings.jl")
    include("wad.jl")
    include("geometry.jl")
    include("color.jl")
    include("sdl_utils.jl")
    include("assets.jl")
    include("collisions.jl")
    include("map.jl")
    include("things.jl")
    include("player.jl")
    include("render3d.jl")
    include("render2d.jl")

    using .Wad
    using .Assets
    using .Players
    using .Maps
    using .Render3d
    using .Colors
    using .Render2d

    function print_fps(start_time)
        msec = SDL_GetTicks() - start_time
        if msec > 0
            fps = 1000 / msec
            println(fps)
        end
    end

    function handle_sdl_events(WINDOW, close, show_automap, show_blockmap, is_fullscreen, take_photo)
        event_ref = Ref{SDL_Event}()
        while Bool(SDL_PollEvent(event_ref))
            evt = event_ref[]
            evt_ty = evt.type
            if evt_ty == SDL_QUIT
                close = true
            elseif evt_ty == SDL_KEYDOWN
                scan_code = evt.key.keysym.scancode
                if scan_code == SDL_SCANCODE_Q 
                close = true
                end
                if scan_code == SDL_SCANCODE_TAB 
                    show_automap = !show_automap
                end
                if scan_code == SDL_SCANCODE_G
                show_blockmap = !show_blockmap
                end
                if scan_code == SDL_SCANCODE_F
                    is_fullscreen = !is_fullscreen
                    SDL_SetWindowFullscreen(WINDOW, is_fullscreen)
                end
                if scan_code == SDL_SCANCODE_R
                    Settings.NO_CLIP = !Settings.NO_CLIP
                end
                if scan_code == SDL_SCANCODE_T
                    Settings.SHOW_FPS = !Settings.SHOW_FPS
                end
                if scan_code == SDL_SCANCODE_E
                take_photo = true
                end
            end
        end
        return WINDOW, close, show_automap, show_blockmap, is_fullscreen, take_photo
    end

    function save_photo(surface, take_photo)
        dir = homedir()
        if !isdir(dir * "/.bsp/photos")
            mkpath(dir * "/.bsp/photos")
        end
        date = Dates.now()
        IMG_SavePNG(surface, dir * "/.bsp/photos/" * Dates.format(date, "yyyy-mm-dd_HH:MM:SS") * ".png")
        return false
    end

    function init_sdl()
        @assert SDL_Init(SDL_INIT_EVERYTHING) == 0 "error initializing SDL: $(unsafe_string(SDL_GetError()))"
        WINDOW = SDL_CreateWindow("Bsp Renderer", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, Settings.WIDTH,  Settings.HEIGHT, SDL_WINDOW_SHOWN)
        SDL_ShowCursor(SDL_FALSE)
        SDL_SetRelativeMouseMode(SDL_TRUE)
        SDL_SetHint("SDL_HINT_MOUSE_RELATIVE_MODE_CENTER", "1")
        SCREEN_SURF = SDL_CreateRGBSurface(0, Settings.WIDTH, Settings.HEIGHT, 32, 0, 0, 0, 0)
        AUTOMAP = SDL_CreateSoftwareRenderer(SCREEN_SURF)
        return WINDOW, SCREEN_SURF, AUTOMAP
    end

    function free_assets(asset_data)
        for sprite in asset_data.sprites
            SDL_FreeSurface(sprite.second.surface)
        end
        for patch in asset_data.patches
            SDL_FreeSurface(patch.second.surface)
        end
        for texture in asset_data.textures
            SDL_FreeSurface(texture.second.surface)
        end
    end

    function run(wads, map)
        
        WINDOW, SCREEN_SURF, AUTOMAP = init_sdl()

        close::Bool = false
        show_automap::Bool = false
        show_blockmap::Bool = false
        take_photo::Bool = false
        is_fullscreen::Bool = false
    
        iwad_name = popat!(wads, 1)
        iwad = Wad.readwad(iwad_name)
        asset_data = Assets.read_asset_data!(iwad)
        map_data = Maps.readmap!(iwad, map)
        for wad_name in wads
            pwad = Wad.readwad(wad_name)
            Assets.overwrite_asset_data!(pwad, asset_data)
            println("overriding asset and map data with $wad_name")
            try
                map_data = Maps.readmap!(pwad, map)
            catch e
                println("no overloading maps found in $wad_name")
            end
        end

        player_thing = Maps.get_player(map_data)
        player = Player(player_thing.x, player_thing.y, player_thing.angle, 41, 41, 16, [0,0])
        try
            Render3d.init_renderer()
            last_frame = 0
            now = SDL_GetPerformanceCounter();
            dt::Float64 = 0
            last_ticks = SDL_GetTicks()
            while !close
                start = SDL_GetTicks()
                if (SDL_GetTicks() - last_ticks < 1000/Settings.FRAME_CAP) 
                    # its likely we have a moment right here to invoke the garbage collector
                    GC.safepoint()
                    continue
                end
                last_ticks = SDL_GetTicks()
                
                last_frame = now
                now = SDL_GetPerformanceCounter()
                dt = (now - last_frame) * 1000 / SDL_GetPerformanceFrequency();
            
                WINDOW, close, show_automap, show_blockmap, is_fullscreen, take_photo = handle_sdl_events(WINDOW, close, show_automap, show_blockmap, is_fullscreen, take_photo)
                update!(player, map_data, (dt / 1000))
                for thing in map_data.things
                    Things.update!(thing, map_data)
                end
                Render3d.init_new_frame()
                win_surf = SDL_GetWindowSurface(WINDOW)
                width = Ref{Int32}()
                height = Ref{Int32}()
                SDL_GetWindowSize(WINDOW, width, height)
                window = SDL_Rect(0,0, width.x+1, height.x+1)
                SDL_FillRect(win_surf, Ref(window), 0)
                # instead of clearing, let shit get trippy. 
                screen_buffer_rect = SDL_Rect(0,0, Settings.WIDTH+1, Settings.HEIGHT+1)
                SDL_FillRect(SCREEN_SURF, Ref(screen_buffer_rect), 0)
                Render3d.render_player_view(SCREEN_SURF, player, map_data, length(map_data.nodes) -1, asset_data)
                if show_automap
                    Render2d.rendermap(AUTOMAP, map_data, player, show_blockmap)
                end
                if take_photo
                    take_photo = save_photo(SCREEN_SURF, take_photo)
                end
                SDL_BlitScaled(SCREEN_SURF, C_NULL, win_surf, Ref(window))
                SDL_UpdateWindowSurface(WINDOW)
                if Settings.SHOW_FPS
                    print_fps(start)
                end
            end
        finally
            free_assets(asset_data)
            SDL_DestroyRenderer(AUTOMAP)
            SDL_DestroyWindow(WINDOW)
            SDL_Quit()
        end
    end
end
