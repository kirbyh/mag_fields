function panel_forces = calc_forces(coil_mp, dL, I, points, omitCoil)
% Calculates the forces from a given geometry on each panel of the array
% and stores the output in a matrix forces [x y z Fx Fy Fz]
% 
% INPUTS : 
%     coil_mp : midpoints of each panel [nPoints x 3] with each row [x,y,z]
%     dL : vector length and direction of each panel corresponding with
%       rows in coil_mp 
%     I : current thru each coil [A]
%     points (optional) : points for the halbach array. If included, this
%       will plot the halbach array and corresponding forces. 
%     omitCoil (optional) : if exists, will omit the coil's effect on
%       itself for the field and force calculations. Requires 'points' to be
%       provided. 
% 
% OUTPUTS : 
%     forces : force vector [N] on each panel location (x,y,z). Coordinate
%     locations match with the coil_mp locations returned by
%     create_halbach.m 
% 
% Kirby Heck
% 02/20/2021

panel_forces = zeros(size(dL)); 
B = zeros(size(dL));  % this is merely for plotting at the end
nPoints = length(panel_forces(:,1)); 

% loop thru each point, omitting the current node
for ii = 1:nPoints
    subset = ones(1, nPoints); 
%     subset(ii) = 0; 
    if ~exist('omitCoil', 'var')
        subset(ii) = 0;  % omit this point
    else
        dims = size(points); 
        nPan = dims(1)-1;  % points in one coil
        start_ind = floor((ii-1)/nPan)*nPan + 1; 
        end_ind = start_ind+nPan-1; 
        subset(start_ind:end_ind) = 0; 
    end
    subset = logical(subset);  % needs to be a logical array, not double
    mp_subset = coil_mp(subset, :); 
    dL_subset = dL(subset,:); 
    
    B(ii,:) = calc_B(coil_mp(ii,:), mp_subset, dL_subset, I); 
    panel_forces(ii,:) = cross(dL(ii,:), B(ii,:));  % lorentz force F = I LxB
end
panel_forces = panel_forces*I; 

if exist('points', 'var')
    plot_halbach(points); 
    hold on; 
    
    plotF = panel_forces./vecnorm(dL,2,2); 
    plotF = plotF/max(plotF, [], 'all');  % normalize
    plotB = B/max(B, [], 'all');  % normalize
    qF = quiver3(coil_mp(:,1), coil_mp(:,2), coil_mp(:,3), ...
        plotF(:,1), plotF(:,2), plotF(:,3), 'Color', 'r'); 
    qB = quiver3(coil_mp(:,1), coil_mp(:,2), coil_mp(:,3), ...
        plotB(:,1), plotB(:,2), plotB(:,3), 'Color', 'b');
    
%     set(qF, 'AutoScale', 'off'); 
    set(qF, 'AutoScaleFactor', 0.5); 
end
end

