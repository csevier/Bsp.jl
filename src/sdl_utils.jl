module SDLUtils
    using SimpleDirectMediaLayer
    using SimpleDirectMediaLayer.LibSDL2

    using ..Colors

    #assumes RGB888
    function write_color_to_surface(x, y, surface, color)
        r,g,b,a = color
        packed_color = Colors.packRGB888((Int64(r), Int64(g), Int64(b), 255))
        de_ref_ptr_to_surface = unsafe_load(surface)
        casted = Base.unsafe_convert(Ptr{UInt32}, de_ref_ptr_to_surface.pixels)
        pixel_location = xy_to_surface_index(x, y,  de_ref_ptr_to_surface.w)
        unsafe_store!(casted, packed_color, pixel_location)
    end

    # if write color to surface is to slow because you have to do it in a loop, using just the index convert_flat_to_surface
    function xy_to_surface_index(x, y, surface_width)
        return surface_width * y + x
    end

    function create_surface(width,height)
        surf = SDL_CreateRGBSurface(0, width, height, 32, 0, 0, 0, 0)
        window = SDL_Rect(0,0, width, height)
        transparency_color =  Colors.packRGB888((152,0,136, 255))
        SDL_FillRect(surf, Ref(window), transparency_color)
        SDL_SetColorKey(surf, SDL_TRUE, transparency_color)
        return surf
    end

    function get_matrix_from_surface(surface)
        de_ref_ptr_to_surface = unsafe_load(surface)
        casted = Base.unsafe_convert(Ptr{UInt32}, de_ref_ptr_to_surface.pixels)
        matrix = zeros(UInt32,  de_ref_ptr_to_surface.w, de_ref_ptr_to_surface.h)
        for x in 1:de_ref_ptr_to_surface.w
            for y in 1:de_ref_ptr_to_surface.h
               index = xy_to_surface_index(x, y, de_ref_ptr_to_surface.w)
               matrix[x, y] = unsafe_load(casted, index)
            end
        end
        return matrix
    end
end