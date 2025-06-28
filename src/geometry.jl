module Geometry
    using ..Settings
    export X_TO_ANGLE_TABLE,
    init_tables,
    is_point_on_leftside,
    rotate,
    norm,
    convert_angle_from_bams,
    distance,
    angle_to_x,
    point_to_angle,
    scale_from_global_angle,
    check_bbox

    X_TO_ANGLE_TABLE::Vector{Float32} = []

    function init_tables()
        global X_TO_ANGLE_TABLE = get_x_to_angle_table()
    end

    function is_player_on_leftside(player, node)
        dx::Float64 = player.x - node.x_partition_start
        dy::Float64 = player.y - node.y_partition_start
        result::Float64 = dx * node.delta_y_partition  - dy * node.delta_x_partition 
        return result <= 0
    end

    function is_player_on_leftside(player, x1, y1, x2, y2)
        dx::Float64 = player.x - x1
        dy::Float64 = player.y - y1
        result::Float64 = dx * y2 - dy * x2
        return result <= 0
    end

    function is_point_on_leftside(x, y, node)
        dx::Float64 = x - node.x_partition_start
        dy::Float64 = y - node.y_partition_start
        result::Float64 = dx * node.delta_y_partition  - dy * node.delta_x_partition 
        return result <= 0
    end

    function rotate(x, y, angle)
        x_prime = x * cos(deg2rad(angle)) - y * sin(deg2rad(angle))
        y_prime = x * sin(deg2rad(angle)) + y * cos(deg2rad(angle))
        return x_prime, y_prime
    end

    function norm(angle)
        angle %= 360
        if angle < 0
            return angle + 360
        end
        return angle
    end

    function norm(value, max)
        value %= max
        if value < 0
            return value + max
        end
        return value
    end

    function convert_angle_from_bams(bam_angle::Int)
        a::Int = bam_angle << 16
        alpha::Float64 =  a * 8.38190317e-8
        if alpha < 0
            return alpha + 360
        else
            return alpha
        end
    end

    function angle_to_x(angle)
        if angle > 0
            x = Settings.SCREEN_DIST - tan(deg2rad(angle)) * Settings.HALF_WIDTH 
        else
            x = -tan(deg2rad(angle)) * Settings.HALF_WIDTH + Settings.SCREEN_DIST
        end
        return trunc(Int, x)
    end

    function point_to_angle(player, vertex)
        dx = vertex[1] - player.x
        dy = vertex[2] - player.y
        at2 =atan(dy, dx)
        return rad2deg(at2)
    end

    function get_x_to_angle_table()
        x_to_angle = []
        for i in 0:Settings.WIDTH + 1
            angle = rad2deg(atan((Settings.HALF_WIDTH - i) /(Settings.SCREEN_DIST)))
            push!(x_to_angle, angle)
        end
        return x_to_angle
    end

    function scale_from_global_angle(x, player, rw_normal_angle, rw_distance)
        x_angle = X_TO_ANGLE_TABLE[x]
        num = Settings.SCREEN_DIST * cos(deg2rad(rw_normal_angle - x_angle - player.angle))
        den = rw_distance * cos(deg2rad(x_angle))

        scale = num / den
        scale = min(Settings.MAX_SCALE, max(Settings.MIN_SCALE, scale))
        return scale
    end

    function check_bbox(player, bbox)
        top = bbox[1]
        bottom = bbox[2]
        left = bbox[3]
        right = bbox[4]
        a = [left, bottom]
        b = [left, top]
        c = [right, top]
        d = [right, bottom]

        px = player.x
        py = player.y
        if px < left
            if py > top
                bbox_sides = [(b, a), (c, b)]
            elseif py < bottom
                bbox_sides = [(b, a), (a, d)]
            else
                bbox_sides = [(b, a)]
            end
        elseif px > right
            if py > top
                bbox_sides = [(c, b), (d, c)]
            elseif py < bottom
                bbox_sides = [(a, d), (d, c)]
            else
                bbox_sides = [(d, c)]
            end
        else
            if py > top
                bbox_sides = [(c, b)]
            elseif py < bottom
                bbox_sides = [(a, d)]
            else
                return true
            end
        end

        for side in bbox_sides
            v1 = side[1]
            v2 = side[2]
            a1 = point_to_angle(player, v1)
            a2 = point_to_angle(player, v2)
            span = norm(a1 - a2)

            a1 -= player.angle
            span1 = norm(a1 + Settings.HALF_FOV)
            if span1 > Settings.FOV
                if span1 >= span + Settings.FOV
                    continue
                end
            end
            return true
        end

        return false
    end
end