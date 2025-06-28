module Collision
using LinearAlgebra

function point_in_point(x1, y1, x2, y2)
    return x1 == x2 && y1 ==y2
end

function point_in_circle(x, y, cx, cy, cr)
    distance_to_circle = LinearAlgebra.norm([x, y] - [cx, cy])
    return distance_to_circle < cr
end

function circle_in_circle(cx1, cy1, cr1, cx2, cy2, cr2)
    distance_between_circles =  LinearAlgebra.norm([cx1, cy1] - [cx2, cy2])
    return distance_between_circles < cr1 + cr2
end

function point_in_rectangle(x, y, rx, ry, rw, rh)
    return x >= rx && x <= rx + rw && y >= ry && y <= ry + rh
end

function rectangle_in_rectangle(rx1, ry1, rw1, rh1, rx2, ry2, rw2, rh2)
    return rx1 + rw1 >= rx2 && rx1 <= rx2 + rw2 && ry1 +rh1 >= ry2 && ry1 <= ry2 + rh2
end

function circle_in_rectangle(cx, cy, cr, rx, ry, rw, rh)
    if cx < rx
        test_x = rx
    elseif cx > rx + rw
        test_x = rx + rw
    end

    if cy < ry
        test_y = ry
    elseif cy > ry + rh
        test_y = ry + rh
    end

    distance_to_rect =  LinearAlgebra.norm([cx, cy] - [test_x, test_y])

    return distance_to_rect <= cr
end

function line_in_point(x1, y1, x2, y2, px, py)
    line_length = LinearAlgebra.norm([x1, y1] - [x2, y2])
    d1 = LinearAlgebra.norm([x1, y1] - [px, py])
    d2 = LinearAlgebra.norm([x2, y2] - [px, py])
    return d1 + d2 == line_length
end

function line_in_circle(x1, y1, x2, y2, cx, cy, cr)
    is_p1_inside = point_in_circle(x1, y1, cx, cy, cr)
    is_p2_inside = point_in_circle(x2,  y2, cx, cy, cr)
    if is_p1_inside || is_p2_inside
        return true
    end

    line_length = LinearAlgebra.norm([x1, y1] - [x2, y2])
    dot = ( ((cx-x1)*(x2-x1)) + ((cy-y1)*(y2-y1)) ) / line_length^2;

    closest_x_on_line = x1 + (dot * (x2-x1))
    closest_y_on_line = y1 + (dot * (y2-y1));

    is_on_seg = line_in_point(x1, y1, x2, y2, closest_x_on_line, closest_y_on_line)
    if !is_on_seg
        return false
    end
    
    distance_from_circle_to_point = LinearAlgebra.norm([closest_x_on_line, closest_y_on_line] - [cx, cy])
    return distance_from_circle_to_point <= cr
end

function line_in_line(x1, y1, x2, y2, x3, y3, x4, y4)
    uA = ((x4-x3)*(y1-y3) - (y4-y3)*(x1-x3)) / ((y4-y3)*(x2-x1) - (x4-x3)*(y2-y1))
    uB = ((x2-x1)*(y1-y3) - (y2-y1)*(x1-x3)) / ((y4-y3)*(x2-x1) - (x4-x3)*(y2-y1))

    intersection_x = x1 + (uA * (x2-x1))
    intersection_y = y1 + (uA * (y2-y1))

    return uA >= 0 && uA <= 1 && uB >= 0 && uB <=1, intersection_x, intersection_y
end

function line_in_rectangle(x1, y1, x2, y2, rx, ry, rw, rh)
    left =   lineLine(x1,y1,x2,y2, rx,ry,rx, ry+rh);
    right =  lineLine(x1,y1,x2,y2, rx+rw,ry, rx+rw,ry+rh);
    top =    lineLine(x1,y1,x2,y2, rx,ry, rx+rw,ry);
    bottom = lineLine(x1,y1,x2,y2, rx,ry+rh, rx+rw,ry+rh);
    return left || right || top || bottom
end
end