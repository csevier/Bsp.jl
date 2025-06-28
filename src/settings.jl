module Settings
    WIDTH::Int = 640
    HEIGHT::Int = 480
    const HALF_WIDTH::Int = WIDTH ÷ 2
    const HALF_HEIGHT::Int = HEIGHT ÷ 2
    const FOV::Int = 90
    const HALF_FOV::Int = 45
    const PLAYER_SPEED::Float64 = 40
    const PLAYER_ROT_SPEED::Float64 = 20
    const SCREEN_DIST::Float64 = HALF_WIDTH / tan(deg2rad(HALF_FOV))
    const MAX_SCALE::Float64 = 64.0
    const MIN_SCALE::Float64 = 0.00390625
    const ONE_HANDED_MODE::Bool = false
    const FRAME_CAP:: Int32 = 30
    NO_CLIP::Bool = false
    SHOW_FPS::Bool = false
end