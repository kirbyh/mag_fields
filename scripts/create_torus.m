function [points, coil_mp, dL] = create_torus(geom, n_coils, radius, pumpkin)
% Creates an nCoil toroidal array with coil geometry given by geom. The 
% output here is to start with the points array for the coil geometries
% and end with a dL array (length/direction of each panel on each coil) and
% a midpoint array (midpoint of each panel)
% 
% INPUTS : 
%     geom : [coil_points x 3] array of points centered around (0,0) that
%       each coil will take the shape of
%     nCoils : number of coils in the Halbach array; should be multiple of
%       four
%     radius : radius of array, in meters
%     pumpkin : (true/false) flips every other coil direction to create a
%       modified torus geometry. Default off. 
% 
% OUTPUTS : 
%     points : [coil_points x 3 x nCoils] array of (x,y,z) points that
%       describe the entire toroidal array
%     coil_mp : [M x 3] array of panel midpoints
%     dL : [M x 3] array of panel vector directions; finite difference
% 
%     note - M is equal to nCoils * (coil_points-1) and is equal to the
%     total number of unique points in the entire array
% 
% Kirby Heck 
% 02/18/2021

coil_points = length(geom(:,1)); 
points = zeros(length(geom), 3, n_coils); 

if ~exist('pumpkin', 'var')
    pumpkin = false; 
    beta = 0; 
end

% create centers to the coils
dtheta = 2*pi/n_coils; 
theta = (0:dtheta:2*pi-dtheta)';  % [n_coils x 1]
centers = radius*[cos(theta), sin(theta), zeros(size(theta))];  % [n_coils x 3]

for ii = 1:n_coils
    if pumpkin
        beta = -(mod(ii, 2)+1)*pi;  % additional angle offset; pumpkin rotation
    end
    
    A = [cos(theta(ii)+beta), -sin(theta(ii)+beta), 0; 
        sin(theta(ii)+beta), cos(theta(ii)+beta), 0; 
        0, 0, 1];  % rotation matrix
    coil = [geom(:,1), zeros(coil_points, 1), geom(:,2)];  % first plot coil in xz-plane
    points(:,:,ii) = centers(ii,:) + (A*coil')'; 
end

% plot_halbach(points, figure); 

% calculate midpoints and length vectors
M = coil_points-1; 
dL = zeros(n_coils * M, 3); 
coil_mp = zeros(size(dL)); 

for ii = 1:n_coils  % ii loops through n-coils
    start_ind = (ii-1)*M + 1; 
    end_ind = ii*M; 
    
    dL(start_ind:end_ind, :) = diff(points(:,:,ii)); % first order finite diff
    coil_mp(start_ind:end_ind, :) = points(1:M,:,ii) + dL(start_ind:end_ind,:)/2;
end

end

