function [isolatingPrimary, backgroundPrimary] = ReceptorIsolateOptimBackgroundMulti(T_receptors,whichReceptorsToIsolate, ...
    whichReceptorsToIgnore,whichReceptorsToMinimize,B_primary,backgroundPrimary,initialPrimary,whichPrimariesToPin,...
    primaryHeadRoom,maxPowerDiff,desiredContrasts,ambientSpd,directionsYoked,directionsYokedAbs,pegBackground)
% [isolatingPrimaries] = ReceptorIsolateOptimBackgroundMulti(T_receptors,whichReceptorsToIsolate, ...
%   whichReceptorsToIgnore,whichReceptorsToMinimize,B_primary,backgroundPrimary,initialPrimary,whichPrimariesToPin,...
%   primaryHeadRoom,maxPowerDiff,desiredContrasts,ambientSpd,directionsYoked,directionsYokedAbs,pegBackground)
%
% This routine finds the background primaries and k modulation
% primaries maximizing the contrast on the specified k modulation
% directions. This is done in simultaneous optimization.
%
% It is also possible to run this routine by passing a background and
% pegging it to the passed settings, such that the optimization does NOT
% find the best background, but only the best modulation primaries.
%
% Input arguments follow largely the function ReceptorIsolate, which finds
% the modulation primaries maximizing the contrast on one given modulation
% direction.
%
% The optimization itself is done around the in-line function
% IsolateFunction, defined below.
%
% Here is some additinal informaiton from Manuel, about how this works:
%
%     (1) Linear constraint. In ReceptorIsolateOptimBackgroundMulti, instead of
%     setting a linear constraint for the receptors which should have zero
%     contrast relative to the background, the contrast-to-be-zeroed is added to
%     the error term. In ReceptorIsolate, this is expressed as a linear equality
%     (all contrasts-to-be-zeroed should be 0). The reason why we have to do
%     this is because while we can calculate the activation of the
%     contrasts-to-be-zeroed outside of the optimization in ReceptorIsolate,
%     this cannot be done in ReceptorIsolateOptimBackgroundMulti because it
%     precisely finds the optimal background simultaneously.
% 
%     (2) Non-linear constraint. In ReceptorIsolateOptimBackgroundMulti, there
%     is a non-linear constraint which sets the upper and lower bounds for the
%     modulation primaries and background primary. The reason why this is done
%     as a non-linear constraint is that if the background shifts from e.g. a
%     standard 0.5 half-on background, not all positive excursions (which
%     maximize contrast) yield in-gamut negative excursions.
% 
%     (3) Error function. The heart ReceptorIsolateOptimBackgroundMulti
%     is how the error function is defined. There are at present three
%     definitions: a) for when the contrasts between receptors are yoked (e.g.
%     LMS, with equal contrast on LMS), b) for when the contrasts are yoked but
%     irregardless of sign (e.g. L-M with 10% on L and -10% on M or so), c) all
%     other cases. Currently, there is the magical number 1000 which scales
%     parts of the error function, and perhaps does so for the cases a-c
%     differently. In any event, when optimizing for multiple modulation
%     directions, the sums just add up.
%
% Input arguments:
%
% T_receptors -              Vector of spectral sensitivities for N receptors
% whichReceptorsToIsolate -  Logical array of size N, indicating which
%                            modulations should be isolated
% whichReceptorsToIgnore -   Logical array of size N, indicating which
%                            modulations should be ignored in the
%                            optimization (i.e. neither isolated nor zeroed)
% whichReceptorsToMinimize - Logical array of size N, indicating which
%                            modulations should be minimized (i.e. driven
%                            towards 0).
%                            NOTE: THIS CURRENTLY DOES NOTHING.
% B_primary -                Array of spectral primaries
% backgroundPrimary -        Background primary, will only be used if background
%                            is pegged using the pegBackground argument.
% initialPrimary -           Starting point for optimization.
% whichPrimariesToPin -      See ReceptorIsolate
% primaryHeadRoom -          See ReceptorIsolate
% maxPowerDiff -             See ReceptorIsolate
% desiredContrasts -         See ReceptorIsolate
% ambientSpd -               See ReceptorIsolate
% directionsYoked -          NEED COMMENT
% directionsYokedAbs -       NEED COMMENT
% pegBackground -            Boolean flag to set if the background should not be
%                            optimized. If set, the k modulation primaries will
%                            nonetheless be found, maximizing contrast on the k
%                            directions.

% 07/18/17  ms      Commented.
% 08/17/17  ms      Further comments.
% 03/27/18  dhb     Comments. Remove nargin checks, because all args are in
%                   fact required.
%           dhb     Check on returned primaries staying within headroom

% Check whether the desired contrasts were passed, and if so check
% consistency of its dimensions.
if ~isempty(desiredContrasts)
    if length(whichReceptorsToIsolate) ~= length(desiredContrasts)
        error('Size of whichReceptorsToIsolate and of desired contrasts vector do not line up')
    end
end

% Figure out how many modulations are to be found. This is k.
nModulations = size(whichReceptorsToIsolate, 2);

% If no ambient light spd is passed, assumingit is zero.
if (isempty(ambientSpd))
    ambientSpd = zeros(size(B_primary,1),1);
end

% Use the initial primary guess for all k+1 primary values to be found
% (background + k modulation primaries)
x = repmat(initialPrimary, 1, nModulations+1);

% Figure out which receptors get zero modulation and set up constraint for this.
for i = 1:nModulations
    whichReceptorsToZero{i} = setdiff(1:size(T_receptors,1),[whichReceptorsToIsolate{i} whichReceptorsToIgnore{i} whichReceptorsToMinimize{i}]);
end

%% Constraints
% (1) Set up the constraints. This follows the same logic as ReceptorIsolate.
% We start with the case where we only want to find ONE modulation
% direction.

% Set up constraints on primary variation, some may stay pinned at their
% background values.  For example, for spectral functions we may not want
% big wiggles at the ends of the visible spectrum, where the sensitivities
% are low.
whichPrimariesToVary = setdiff(1:size(B_primary,2),whichPrimariesToPin);
boundIndex = [whichPrimariesToPin whichPrimariesToVary];
[~,sortIndex] = sort(boundIndex);

% Since our modulations are symmetric, we need to make sure that we're not
% out of gamut if our background is not constant across wl band. For a
% half-on background, both the positive and the negative poles of a
% modulation will be in gamut, but that's not necessary the case if the
% background is not 0.5 for all wl bands.
%
% The following piece of code may also only work just right if we're
% not pinning primaries.
vub = backgroundPrimary; vub(:) = 1-primaryHeadRoom;
vlb = backgroundPrimary; vlb(:) = primaryHeadRoom;
vlb(whichPrimariesToPin) = initialPrimary(whichPrimariesToPin);
vub(whichPrimariesToPin) = initialPrimary(whichPrimariesToPin);

% Set up the smoothness constraint.
vectorLength = size(B_primary, 1);
C1 = zeros(vectorLength-1, vectorLength);
for i = 1:vectorLength-1
    C1(i,i) = 1;
    C1(i,i+1) = -1;
end

C2 = zeros(vectorLength-1, vectorLength);
for i = 1:vectorLength-1
    C2(i,i) = -1;
    C2(i,i+1) = 1;
end

% Stack the two constraint matrices and premultiply
% by the primary basis.
C = [C1 ; C2]*B_primary;

% Tolerance vector, just expand passed maxPowerDiff.
Q = ones(2*(vectorLength-1), 1)*1000*maxPowerDiff;
Qx = repmat(Q, 1, nModulations+1);

% Construct the smoothness constraint
theString = 'C';
for i = 1:nModulations
    theString = [theString ',C'];
end
eval(['Cx = blkdiag(' theString ');']);

% (2) Set up the contraints for the background primary and all modulation
% primaries. These are of size k.
vlbx = repmat(vlb, 1, nModulations+1);
vubx = repmat(vub, 1, nModulations+1);

% If the background shouldn't be changed (i.e. pegged), just set the lower
% and upper constraint for that column to be the background primary.
if pegBackground
    vlbx(:, 1) = backgroundPrimary;
    vubx(:, 1) = backgroundPrimary;
end

%% Do the optimization.
options = optimset('fmincon');
options = optimset(options,'Diagnostics','off','Display','off','LargeScale','off','Algorithm','sqp', 'MaxFunEvals', 100000, 'TolFun', 1e-10, 'TolCon', 1e-10, 'TolX', 1e-10);
x = fmincon(@(x) IsolateFunction(x,B_primary,ambientSpd,T_receptors,...
    whichReceptorsToIsolate,whichReceptorsToZero,whichReceptorsToMinimize,...
    nModulations,directionsYoked,directionsYokedAbs),x,Cx,Qx,[],[],vlbx,vubx,@(x)nonlconstraint(x, nModulations),options);

% Extract the output arguments to be passed back.
% This enforces a sanity check on the primaries.
primaryTolerance = 1e-6;
x(x > 1 - primaryHeadRoom & x < 1 - primaryHeadRoom + primaryTolerance) = 1 - primaryHeadRoom;
x(x < primaryHeadRoom & x > primaryHeadRoom-primaryTolerance) = primaryHeadRoom;
if (any(x > 1 - primaryHeadRoom))
    error('Primary greater than 1 minus headroom');
end
if (any(x < primaryHeadRoom))
    error('Primeary less than primary headroom');
end
backgroundPrimary = x(:, 1);
for i = 1:nModulations+1
    isolatingPrimary{i} = x(:, i);
end

end

% f = IsolateFunction(x,B_primary,ambientSpd,T_receptors,whichReceptorsToIsolate,whichReceptorsToZero,whichReceptorsToMinimize,nModulations,directionsYoked, directionsYokedAbs)
%
% Optimization subfunction.  This mixes maximizing response of isolated
% receptors with smoothness.
function f = IsolateFunction(x,B_primary,ambientSpd,T_receptors,whichReceptorsToIsolate,whichReceptorsToZero,whichReceptorsToMinimize,nModulations,directionsYoked,directionsYokedAbs)

% Compute background including ambient
backgroundSpd = B_primary*x(:, 1) + ambientSpd;

% Iterate over the modulations and calculate contrasts
for i = 2:nModulations+1
    % Compute contrasts for receptors we want to isolate
    modulationSpd = B_primary*(x(:, i)-x(:, 1));
    isolateContrasts{i-1} = T_receptors(whichReceptorsToIsolate{i-1},:)*modulationSpd ./ (T_receptors(whichReceptorsToIsolate{i-1},:)*backgroundSpd);
    zeroContrasts{i-1} = T_receptors(whichReceptorsToZero{i-1},:)*modulationSpd ./ (T_receptors(whichReceptorsToZero{i-1},:)*backgroundSpd);
end

% Here, we calculate the error term for the optimization.
theSum = 0;
for i = 1:nModulations
    if directionsYoked(i)
        % Case for when the receptors should see the same amount of
        % contrast
        theSum = theSum + 1000*sum( (isolateContrasts{i}  - (sum(isolateContrasts{i})/length(whichReceptorsToIsolate{i})) ).^2 ) + sum((isolateContrasts{i}-1).^2) + 1000*sum(zeroContrasts{i}.^2);
    elseif directionsYokedAbs(i)
        % Case for when the receptors should see the same amount of
        % contrast, regardless of sign (e.g. 10% L, -10% M contrast)
        theSum = theSum + 1000*sum( isolateContrasts{i} )  + sum((isolateContrasts{i}-1).^2) + 1000*sum(zeroContrasts{i}.^2);
    else
        theSum = theSum + sum((isolateContrasts{i}-1).^2) + 1000*sum(zeroContrasts{i}.^2);
    end
end
f = theSum;
end

% Set up upper and lower bounds as a non-linear constraint. Since the
% background is changing within the optimization, we won't be able to know
% the excursion unless we have the background...
function [c ceq] = nonlconstraint(x, nModulations)
backgroundPrimary = x(:, 1);
c = [];
for i = 1:nModulations+1
    isolatingPrimary{i} = x(:, i);
    
    c1 = -([backgroundPrimary isolatingPrimary{i}]*[2 -1]');
    c2 = [backgroundPrimary isolatingPrimary{i}]*[2 -1]' - 1;
    
    c3 = -([backgroundPrimary isolatingPrimary{i}]*[0 1]');  % negative arm
    c4 = [backgroundPrimary isolatingPrimary{i}]*[0 1]' - 1; % positive arm
    
    c = [c c1 c2 c2 c3];
end
ceq = [];
end