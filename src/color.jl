module Colors
    function packARGB8888(rgba_tuple::Tuple{Int64, Int64, Int64, Int64})::UInt32
        r,g,b,a = rgba_tuple
        packed::UInt32 = 0
        packed |= (r << 24)
        packed |= (g << 16) 
        packed |= (b << 8) 
        packed |= (a << 0) 
        return packed
    end

    function packRGB888(rgba_tuple::Tuple{Int64, Int64, Int64, Int64})::UInt32
        r,g,b,a = rgba_tuple
        packed::UInt32 = 0
        packed |= (r << 16)
        packed |= (g << 8) 
        packed |= (b << 0) 
        return packed
    end

    function unpack(color::UInt32)::Tuple{Int64, Int64, Int64, Int64}
        bytes = reinterpret(UInt8, [color])
        a = Int64(bytes[4])
        r = Int64(bytes[3])
        g = Int64(bytes[2])
        b = Int64(bytes[1])
        return (r, g, b, a)
    end
end