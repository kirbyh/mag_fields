function varargout = parasitic_shielding(points, coil_mp, dL, varargin)
% Quantifies the number of particles [protons] that would NOT have hit the
% spacecraft of threshold 'thresh' that now do as a result of the magnetic
% shielding. 
% 
% USEAGE : 
%     parasitic_shielding(points, coil_mp, dL) calculates the shielding
%       rate of the specified wire geometry with N=1000 particles for
%       current I=1e6 A, KE=1 MeV, relativistic EOM, randomly sampled
%       initial positions, radially inward initial velocities, threshold
%       value of 3 [m]
%     parasitic_shielding(points, coil_mp, dL, ...) allows the 
%       specification of any of the parameters below (see VARIABLE INPUTS)
% 
% INPUTS : 
%     Variable input arguments after points, coil_mp, and dL: 
%     points : [pointsPerCoil x 3 x n_coils] array prescribing shield
%       geometry
%     coil_mp : midpoints of each panel [nPoints x 3] with each row [x,y,z]
%     dL : [nPoints x 3] vector length and direction of each panel 
%       corresponding with rows in coil_mp 
% 
% VARIABLE INPUTS : 
%     I : current [A], default is 1e6 [A]
%     KE : Kinetic energy in eV, default is 1e8 eV. Use 'powerlog' for 
%       power-log distrubtion
%     plots : controls plotting, default is 'off'
%     rel : relativistic EOM, default is 'on'
%     randPos : randomly generated initial conditions, default is 'on'
%     N : number of particle to sample, default is 1e5. Large N (>> 10^3)
%       is recommended for reasonable accuracy
%     thresh : size of spaceship, default is 1.5 [m]
%     seed : set seed, default is 10. Use 'noseed' for random seed. 
%     sampling : sampling rate that determines how many times as many
%       particles will be shot that actually hit if left undeflected. e.g.
%       sampling=2, N=1000 will pick ~500 initial trajectories that
%       actually intersect the spacecraft. 
%     randDir : Method to sample direction vectors from, default is 'thresh':
%       'iso' - sample isotropically
%       'thresh' - sample within the sampling threshold above
%       'inward' - sample isotropically inward only
%     
% OUTPUTS : 
% ONE OUTPUT REQUESTED : 
%     defl_rate : adjusted deflection rate  accounting for parasitic
%     radiation
% TWO OUTPUTS REQUESTED : 
%     defl_rate (see above)
%     par_rate : number of parasitic particles divided by the number of
%       properly deflected particles
% THREE OUTPUTS REQUESTED : 
%     ICs : initial conditions (either dimensional for non-relativistic or
%       non-dimensional for relativistic) that particles were shot at. 
%     res : hit/miss for each respective energy with shield on
%     res_0 : hit/miss for each respective energy with no active magnetic
%       shielding (undeflected trajectory)
% 
% INTERNAL PARAMETERS : 
%     r_sphere : starting point of particles
%     r_plot : radius to show in plots
% 
% Kirby Heck
% 3/27/21

%% PARSE VARIABLES
if nargin < 3
    error('Not enough input arguments')
end

p = inputParser; 
onoff = {'on','off'};
randDirInputs = {'iso', 'thresh', 'inward'}; 
checkonoff = @(x) any(validatestring(x,onoff));
checkvaliddir = @(x) any(validatestring(x,randDirInputs)); 
checkvalidKE = @(x) isnumeric(x) || isequal(x, 'powerlog'); 
checkvalidseed = @(x) isnumeric(x) || isequal(x, 'noseed'); 

addParameter(p, 'I', 1e6, @isnumeric)
addParameter(p, 'KE', 1e8, checkvalidKE)
addParameter(p, 'plots', 'off', checkonoff)
addParameter(p, 'rel', 'on', checkonoff)
addParameter(p, 'randPos', 'on', checkonoff)
addParameter(p, 'N', 100, @isnumeric)
addParameter(p, 'thresh', 1.5, @isnumeric)
addParameter(p, 'seed', 10, checkvalidseed)
addParameter(p, 'sampling', 2, @isnumeric)
addParameter(p, 'randDir', 'thresh', checkvaliddir) 

parse(p, varargin{:}); 

% set variables
truefalse = @(onoff) isequal(onoff, 'on'); 
I = p.Results.I; 
KE = p.Results.KE; 
plots = truefalse(p.Results.plots); 
rel = truefalse(p.Results.rel); 
randPos = truefalse(p.Results.randPos); 
N = p.Results.N; 
thresh = p.Results.thresh; 
sampling = p.Results.sampling; 
randDir = p.Results.randDir; 

% set seed if requested; default is 10
if isnumeric(p.Results.seed)
    SEED = p.Results.seed; 
    rng(SEED); 
end

%% testing setup (uncomment)
% AR = 0.8688;
% C_r = 1.8296;
% H_r = 3.9432;
% 
% geom = coil_racetrack(C_r, AR, 33); 
% [points, coil_mp, dL] = create_halbach(geom, 8, H_r); 

%% Create Sphere For Initial Positions
r_sphere = 50;  % begin particles at 50 m away

if randPos
    theta = 2*pi*rand(N, 1); 
    phi = acos(2*rand(N,1)-1); 
    
    r_0(:,1) = sin(phi).*cos(theta); 
    r_0(:,2) = sin(phi).*sin(theta); 
    r_0(:,3) = cos(phi); 
else % evenly spaced points on sphere, not recommended
    nSphere = ceil(sqrt(N));
    [X,Y,Z] = sphere(nSphere);

    r_0 = [X(:), Y(:), Z(:)];  % rearrange sphere
    r_0 = unique(r_0,'rows');
    theta = atan2(r_0(:,2), r_0(:,1));  % theta values 
    phi = real(acos(r_0(:,3)./vecnorm(r_0,2,2)));  % phi values; need these for random directions
end
r_0 = r_0*r_sphere; 
nRuns = length(r_0(:,1));  % THIS MAY BE DIFFERENT FROM N

% print banner
disp('========= Field Effectiveness =========')
disp(['  Testing field with N=' num2str(nRuns) ' runs']); 
disp('  Timer start'); 
tic; 

%% Calculate energy and momentum 
% set direction method
if isequal(randDir, 'thresh')
    SAMPLE_THRESH = thresh*sqrt(sampling);  % [sampling]x larger threshold radius to sample from
else
    SAMPLE_THRESH = r_sphere-1e-5;  % inward sampling
end

% calculate directions
if exist('SEED', 'var')
    if isequal(randDir, 'iso')
        v_hat = sampleRandDir(nRuns, SEED); 
    else
        v_hat = sampleDirVector(phi, theta, r_sphere, SAMPLE_THRESH, SEED);
    end
else
    if isequal(randDir, 'iso')
        v_hat = sampleRandDir(nRuns); 
    else
        v_hat = sampleDirVector(phi, theta, r_sphere, SAMPLE_THRESH);
    end
end

m = 1.67262e-27;  % mass of proton [kg]
e = 1.6022e-19;  % charge on a proton, conversion from eV to J 
q = e;  % charge of particle [C]
c = 299792458;  % speed of light, m/s
B_0 = 1; 

R = m*c/q/B_0;  % Larmor radius
omega_0 = q*B_0/m; % cyclotron frequency
if ~isnumeric(KE)  % request random sampling kinetic energy
    KE = samplePowerlog(nRuns);  % default 1e6 eV to 1e9 eV
else
    KE = repmat(KE, [nRuns, 1]);  % convert to column vector
end
KE_J = KE*e; 
v = c*sqrt(1-(m*c^2./(KE_J+m*c^2)).^2);  % relativistic velocity to calculate tspan
p_hat = sqrt((1+KE_J./m/c^2).^2-1);

if rel
    ICs = [r_0/R, v_hat.*p_hat];
else
    ICs = [r_0, v_hat.*v];  % NON-RELATIVISTIC EOM CHECK
end

%% Set global vars
GL('I', I);
GL('coil_mp', coil_mp);
GL('dL', dL);
if rel
    GL('r_0', R); 
else
    GL('r_0', 1); 
end

%% Begin ODE45 integrations
res = zeros(nRuns, 1); 
res_0 = zeros(nRuns, 1); 

if plots
    streaks = cell(nRuns, 1);  % preallocate :)
    streaks_0 = cell(nRuns, 1);  % undeflected streaks
end
% === CALCULATE RUNS WITH CURRENT ON ===
for ii = 1:nRuns
    t = [0 2*r_sphere/v(ii)]; 
    s = omega_0*t; 
    
    IC_i = ICs(ii,:);
    if rel % ode45 integration
        [~, traj] = ode45(@eom_rad_rel, s, IC_i);
        traj = traj*R;  % re-scale position to dimensionalize
    else
        [~, traj] = ode45(@eom_rad, t, IC_i); 
    end
    trail = traj(:,1:3);  % xyz trail of points
    
    % check to see if the trail intersepts the sphere bounded by 'thresh'
    mags = vecnorm(trail,2,2); 
    [~,ind] = min(mags);  % find index of nearest approach
    
    if ind == length(trail)  % nearest point to origin is at the end
        res(ii) = does_it_hit(trail(ind,:), trail(ind-1,:), thresh);
    elseif ind == 1
        res(ii) = does_it_hit(trail(ind,:), trail(ind+1,:), thresh); 
    else  % if nearest isn't at the end...
        if mags(ind+1)<mags(ind-1)  % check if next nearest point is ahead 
            res(ii) = does_it_hit(trail(ind,:), trail(ind+1,:), thresh);
        else  % nearest point must be behind
            res(ii) = does_it_hit(trail(ind,:), trail(ind-1,:), thresh);
        end
    end
    
    % store trajectories for plotting if true
    if plots
        streaks{ii} = trail; 
    end
    
    % handy print statment for large runs
    if mod(ii, 1000) == 0
        fprintf('  Completed %i runs out of %i\n', ii, nRuns); 
    end
end

% === CALCULATE WITH CURRENT OFF ===
for ii = 1:nRuns
    t = [0 2*r_sphere/v(ii)]; 
    s = omega_0*t; 
    
    % calculate hits with point and direction
    if rel
        point1 = ICs(ii, 1:3)*R; 
        point2 = point1 + ICs(ii, 4:6)*max(s); 
    else
        point1 = ICs(ii, 1:3); 
        point2 = point1 + ICs(ii, 4:6)*max(t); 
    end
    res_0(ii) = does_it_hit(point1, point2, thresh); 
    
    if plots % if plotting, then we're going to need the trails (Not recommended)
        GL('I', 0);  % set global current to zero
        IC_i = ICs(ii,:);
        if rel % ode45 integration
            [~, traj] = ode45(@eom_rad_rel, s, IC_i);
            traj = traj*R;  % re-scale position to dimensionalize
        else
            [~, traj] = ode45(@eom_rad, t, IC_i); 
        end
        streaks_0{ii} = traj(:,1:3);  % xyz trail of points
    end
end

% useful metric is the number of 
res = logical(res); 
res_0 = logical(res_0); 
nParasitic = sum(res & ~res_0);     % entrained particles
nDeflected = sum(~res & res_0);     % successful deflections
nInitial = sum(res_0);              % total hits with shield off

defl_rate = (nDeflected-nParasitic)/nInitial; 
par_rate = nParasitic/(nDeflected+1e-7); 

% output vars
if nargout == 1
    varargout = {defl_rate}; 
elseif nargout == 2
    varargout = {defl_rate, par_rate}; 
else
    varargout = {ICs, res, res_0}; 
end

%% Finish plots
if plots
    r_plot = 8;
    LineSp = {'g:', 'r-'}; 
%     LineSp = {'k:', 'k:'}; 
    LineTh = [0.25, 0.5];  % set up some linespec options in advance
    
    % === PLOT WITH SHIELD ON === 
    f1 = figure();  
    for ii = 1:nRuns  % plot trajectories
        x = streaks{ii}(:,1);
        y = streaks{ii}(:,2);
        z = streaks{ii}(:,3);
        plot3(x, y, z, LineSp{res(ii)+1}, 'LineWidth', LineTh(res(ii)+1)); 
        hold on;
    end
    
    plot_halbach(points, f1)
    axis equal; 
    xlim([-r_plot r_plot])
    ylim([-r_plot r_plot])
    zlim([-r_plot r_plot])
    set(gca, 'Color', [0.5, 0.5, 0.5]); 
    view(3)
    
    xlabel('$x$ [m]'); 
    ylabel('$y$ [m]');
    zlabel('$z$ [m]');
    
    Title = sprintf('Shield on for $N$=%i particles, %.3f effective', nRuns, defl_rate);  
    title(Title); 
    
    % === ALSO PLOT WITH SHIELD OFF ===
    f2 = figure();  
    for ii = 1:nRuns  % plot trajectories
        x = streaks_0{ii}(:,1);
        y = streaks_0{ii}(:,2);
        z = streaks_0{ii}(:,3);
        plot3(x, y, z, LineSp{res_0(ii)+1}, 'LineWidth', LineTh(res(ii)+1)); 
        hold on;
    end
    plot_halbach(points, f2); 
    axis equal; 
    xlim([-r_plot r_plot])
    ylim([-r_plot r_plot])
    zlim([-r_plot r_plot])
    set(gca, 'Color', [0.5, 0.5, 0.5]); 
    view(3)
    
    xlabel('$x$ [m]'); 
    ylabel('$y$ [m]');
    zlabel('$z$ [m]');
    
    Title = sprintf('Shield off for $N$=%i particles, %.3f parasitic', nRuns, par_rate);  
    title(Title); 
end

toc; 

end