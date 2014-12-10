% ReceptorIsolateDemo
%
% Let's find a modulation that isolates various
% photopigments, for various device models.
%
% 3/30/12  dhb      Wrote it.
% 2/3/13   ms       Updated to match changed ReceptorIsolate syntax.
% 4/19/13  dhb, ms  Got this working again.

%% Clear and close
clear; close all;

%% Run us in our home directory
cd(fileparts(mfilename('fullpath')));

%% Which to do?
fprintf('Available receptor models:\n');
fprintf('\t[1]  Human cones and melanopsin\n');
fprintf('\t[2]  Dog\n');
whichModelNumber = GetWithDefault('Enter model',1);
switch (whichModelNumber)
    case 1
        whichModel = 'HumanPhotopigments';
    case 2
        whichModel = 'Dog';
    otherwise
        error('Unknown primaries entered');
end

%% Prompt for device to compute with respect to
fprintf('\nAvailable devices:\n');
fprintf('\t[1]  Spectral - ideal spectral producing device\n');
fprintf('\t[2]  OneLight - calibration data from our OneLight\n');
fprintf('\t[3]  Monitor - some typical monitor\n');
whichPrimaryNumber = GetWithDefault('Enter device',1);
switch (whichPrimaryNumber)
    case 1
        whichPrimaries = 'Spectral';
    case 2
        whichPrimaries = 'OneLight';
    case 3
        whichPrimaries = 'Monitor';
    otherwise
        error('Unknown primaries entered');
end

%% Define primaries and conditions on them
switch (whichPrimaries)
    case 'Spectral'
        % Shows computations in the spectral domain, for
        % a fictional device that can produce delta function
        % primaries at each wavelength with unit power.
        S = WlsToS((400:4:700)');
        B_primary = eye(S(3));
        backgroundPrimary = 0.5*ones(size(B_primary,2),1);
        
        % Pin first and last primaries at their background value.
        whichPrimariesToPin = [1 size(B_primary,1)];
        
        % Leave no headroom for this ideal device
        primaryHeadRoom = 0;
        
        % Set ambient to zero for this ideal device
        ambientSpd = zeros(size(B_primary,2),1);
        
        % No smoothness
        maxPowerDiff = 10000;
        
        receptorIsolateMode = 'Standard';
        
    case 'OneLight'
        % Get some OneLight primary basis
        calPath = fullfile(fileparts(mfilename('fullpath')), 'cals', 'OneLightCal.mat');
        load(calPath);
        S = cal.describe.S;
        B_primary = cal.computed.pr650M;
        ambientSpd = cal.computed.pr650MeanDark;
        
        % Half on in OneLight primary space
        backgroundPrimary = 0.5*ones(size(B_primary,2),1);
        
        % Don't pin
        whichPrimariesToPin = [];
        primaryHeadRoom = 0.02;
        
        % No smoothness
        maxPowerDiff = 10^-1.5;
        receptorIsolateMode = 'Standard';
        
        
    case 'Monitor'
        S = WlsToS((400:4:700)');
        cal = LoadCalFile('DogScreen1NoLights');
        B_primary = SplineSpd(cal.S_device,cal.P_device,S);
        backgroundPrimary = [0.5 0.5 0.5]';
        ambientSpd = SplineSpd(cal.S_ambient,cal.P_ambient,S);
        
        whichPrimariesToPin = [];
        primaryHeadRoom = 0;
        
        % No smoothness
        maxPowerDiff = Inf;
        
        receptorIsolateMode = 'Standard';
end

%% Get sensitivities and set other relvant parameters
switch (whichModel)
    case 'HumanPhotopigments';
        observerAgeInYears = GetWithDefault('> Observer age in years?', 32);
        fieldSizeDegrees = GetWithDefault('> Field size in degrees?', 27.5);
        pupilDiameterMm = GetWithDefault('> Pupil diameter?', 27.5);
        photoreceptorClasses = {'LCone', 'MCone', 'SCone', 'Melanopsin', 'Rods', 'LConeHemo', 'MConeHemo', 'SConeHemo'};
        
        % Make sensitivities for L, M, S, Mel
        T_receptors = GetHumanPhotopigmentSS(S, photoreceptorClasses, fieldSizeDegrees, observerAgeInYears, pupilDiameterMm, [], []);
        
        %% Which to do?
        fprintf('Available directions:\n');
        fprintf('\t[1]  Melanopsin\n');
        fprintf('\t[2]  Melanopsin (controlling for penumbral cones)\n');
        fprintf('\t[3]  SCones)\n');
        whichDirectionNumber = GetWithDefault('Enter direction',1);
        switch (whichDirectionNumber)
            case 1
                whichDirection = 'MelanopsinDirectedLegacy';
                whichReceptorsToIsolate = [4];
                whichReceptorsToIgnore = [5 6 7 8];
                whichReceptorsToMinimize = [];
            case 2
                whichDirection = 'MelanopsinDirected';
                whichReceptorsToIsolate = [4];
                whichReceptorsToIgnore = [5];
                whichReceptorsToMinimize = [];
            case 3
                whichDirection = 'SDirected';
                whichReceptorsToIsolate = [3];
                whichReceptorsToIgnore = [5 8];
                whichReceptorsToMinimize = [];
            otherwise
                error('Unknown direction entered');
        end
        
        
    case 'Dog';
        % Dog cone and rod receptors
        load T_dogrec
        T_receptors = SplineCmf(S_dogrec,T_dogrec,S);
        photoreceptorClasses = {'L cones', 'S cones' 'Rods' };
        
        % Which receptor to ignore?
        whichReceptorsToIgnore = [];
        
        % Desired contrast in isolated direction
        desiredContrast = [];
        
        %% Which to do?
        fprintf('Available directions:\n');
        fprintf('\t[1]  Dog L cones\n');
        fprintf('\t[2]  Dog S cones)\n');
        fprintf('\t[3]  Dog Rods)\n');
        whichDirectionNumber = GetWithDefault('Enter direction',1);
        switch (whichDirectionNumber)
            case 1
                whichDirection = 'DogL';
                whichReceptorsToIsolate = [1];
                whichReceptorsToIgnore = [];
                whichReceptorsToMinimize = [];
            case 2
                whichDirection = 'DogS';
                whichReceptorsToIsolate = [2];
                whichReceptorsToIgnore = [];
                whichReceptorsToMinimize = [];
            case 3
                whichDirection = 'DogRods';
                whichReceptorsToIsolate = [3];
                whichReceptorsToIgnore = [];
                whichReceptorsToMinimize = [];
            otherwise
                error('Unknown direction entered');
        end
        
end

%% Normalize receptors
for i = 1:size(T_receptors,1)
    T_receptors(i,:) = T_receptors(i,:)/max(T_receptors(i,:));
end

% Ask if we want to maximize contrast, or peg contrast
maxContrast = GetWithDefault('> Maximize contrast? [1 = yes, 0 = no]', 1);

if maxContrast
    desiredContrast = [];
elseif ~maxContrast
    desiredContrast = GetWithDefault('> Desired contrast?', 0.45);
end

fprintf('\n> Generating stimuli which isolate receptor classes');
for i = 1:length(whichReceptorsToIsolate)
    fprintf('\n  - %s', photoreceptorClasses{whichReceptorsToIsolate(i)});
end
fprintf('\n> Generating stimuli which ignore receptor classes');
if ~(length(whichReceptorsToIgnore) == 0)
    for i = 1:length(whichReceptorsToIgnore)
        fprintf('\n  - %s', photoreceptorClasses{whichReceptorsToIgnore(i)});
    end
else
    fprintf('\n  - None');
end
% Calculate the receptor activations to the background
modulationPrimary = ReceptorIsolateWrapper(receptorIsolateMode, T_receptors,...
    whichReceptorsToIsolate, whichReceptorsToIgnore, whichReceptorsToMinimize, ...
    B_primary, backgroundPrimary, backgroundPrimary, whichPrimariesToPin,...
    primaryHeadRoom, maxPowerDiff, desiredContrast, ambientSpd);


%% Background spd.  Make sure is within primaries.
% Need to make sure we start optimization at background,
% or else the constraints don't work so well.
backgroundReceptors = T_receptors*(B_primary*backgroundPrimary + ambientSpd);

diffReceptors = T_receptors*B_primary*(modulationPrimary - backgroundPrimary);
contrastReceptors = diffReceptors ./ backgroundReceptors;
for j = 1:size(T_receptors,1)
    fprintf('  - %s: contrast = \t%f\n',photoreceptorClasses{j},contrastReceptors(j));
end


%% Plot
plotDir = 'ReceptorIsolateDemoPlots';
if ~isdir(plotDir);
    mkdir(plotDir);
end
curDir = pwd;
cd(plotDir);

% Sensitivities
theFig1 = figure; clf; hold on
plot(SToWls(S),T_receptors);
savefigghost(sprintf('%s_%s_%s_Sensitivities.pdf',whichModel,whichPrimaries,photoreceptorClasses{whichReceptorsToIsolate}),theFig1,'pdf');

% Modulation spectra
theFig2 = figure; hold on
plot(SToWls(S),B_primary*modulationPrimary,'r','LineWidth',2);
plot(SToWls(S),B_primary*backgroundPrimary,'k','LineWidth',2);
title(sprintf('%s, %s, Isolating: %s; isolated contrast: %0.1f',whichModel,whichPrimaries, photoreceptorClasses{whichReceptorsToIsolate},contrastReceptors(whichReceptorsToIsolate)));
xlim([380 780]);
xlabel('Wavelength');
ylabel('Power');
pbaspect([1 1 1]);
savefigghost(sprintf('%s_%s_%s_Modulation.pdf',whichModel,whichPrimaries,photoreceptorClasses{whichReceptorsToIsolate}),theFig2,'pdf');

% Primaries
theFig3 = figure; hold on
plot(modulationPrimary,'r','LineWidth',2);
plot(backgroundPrimary,'k','LineWidth',2);
title(sprintf('%s, %s, Isolating: %s; primary settings',whichModel,whichPrimaries, photoreceptorClasses{whichReceptorsToIsolate}));
xlim([0 length(backgroundPrimary)]);
ylim([0 1]);
xlabel('Primary');
ylabel('Setting');
savefigghost(sprintf('%s_%s_%s_Primaries.pdf',whichModel,whichPrimaries,photoreceptorClasses{whichReceptorsToIsolate}),'pdf');

cd(curDir);