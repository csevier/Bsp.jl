module Wad
    export DirectoryEntry, 
            WadData, 
            readwad, 
            readheader!,
            readdirectory!,
            getlump_directory_index,
            getlump_data

    struct DirectoryEntry
        name::String
        size::Int32
        offset::Int32
    end

    mutable struct WadData
        type::String
        lumps::Int32
        lumpoffset::Any 
        directory::Vector{DirectoryEntry}
        allbytes::IOBuffer
        WadData() = new("", 0, 0, [])
    end

    function readwad(wad_path::String)
        wad = WadData()
        wad_file = open(wad_path, "r")
        allbytes = read(wad_file)
        wad.allbytes = IOBuffer(allbytes)
        close(wad_file)
        readheader!(wad)
        readdirectory!(wad)
        return wad
    end

    function readheader!(wad::WadData)
        wad.type = String(read(wad.allbytes, 4))
        wad.lumps = read(wad.allbytes, Int32)
        wad.lumpoffset = read(wad.allbytes, Int32)
    end

    function readdirectory!(wad::WadData)
        seek(wad.allbytes, wad.lumpoffset)
        for i in 1:wad.lumps
            offset = read(wad.allbytes, Int32)
            size = read(wad.allbytes, Int32)
            name = strip(String(read(wad.allbytes,8)),'\0')
            de = DirectoryEntry(name, size, offset)
            push!(wad.directory, de)
        end
    end

    function getlump_directory_index(wad::WadData, lumpname)
        for (index, entry) in enumerate(wad.directory)
            if entry.name == lumpname || entry.name == uppercase(lumpname) || entry.name == lowercase(lumpname)
                return index
            end
        end
        return 0
    end

    function getlump_data(wad::WadData, lumpentry::DirectoryEntry)
        seek(wad.allbytes, lumpentry.offset)
        return read(wad.allbytes, lumpentry.size)
    end
end