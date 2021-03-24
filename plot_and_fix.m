%
% Plot the bathymetry and fix some small issues
%

%% Initial setup

% clean up workspace
clear 
close all

%% Fix an issue with delY

% copy
!mv topo_outputs/delY topo_outputs/delY_pre

% read in 
fid = fopen('topo_outputs/delY_pre', 'r', 'ieee-be');
dy = fread(fid, 'float64');
fclose(fid);

% plot
plot(dy)

% write out
fid = fopen('topo_outputs/delY', 'w', 'ieee-be');
fwrite(fid, dy, 'float64');
fclose(fid);

%% Read the bathymetry files

% set file location
fid = 'topo_outputs/sowise_gyre_bathy_fixed.nc';

% read in data
lat = ncread(fid, 'lat');
lon = ncread(fid, 'lon');
bathy = ncread(fid, 'bathy');
draft = ncread(fid, 'draft');
omask = ncread(fid, 'omask');
imask = ncread(fid, 'imask');

% make grid
[x,y] = meshgrid(lon,lat);

%% Make some plots

figpos = [236 70 1092 700];

figure('color','w','position',figpos)
pcolor(x,y,omask')
shading flat
colorbar
title('Ocean mask');

figure('color','w','position',figpos)
pcolor(x,y,imask')
shading flat
colorbar
title('Ice mask');

figure('color','w','position',figpos)
pcolor(x,y,bathy')
shading flat
colorbar
title('Bathymetry [m]');

figure('color','w','position',figpos)
pcolor(x,y,draft')
shading flat
colorbar
title('Ice draft [m]');