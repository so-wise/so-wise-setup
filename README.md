# so-wise-setup
Repository for setting up SO-WISE model configurations

# Setup for the SO-WISE (gyre) congifuration

 This page describes the creation of the domain and forcing files used in the SO-WISE gyre configuration. It is a record for transparency and reproducibility. 

We can base the initial configuration around B-SOSE and two setup from Kaitlin Naughten. 

FRIS999 setup: [https://github.com/knaughten/UaMITgcm/tree/master/example/FRIS_999](https://github.com/knaughten/UaMITgcm/tree/master/example/FRIS_999)

WFRIS999 setup: [https://github.com/knaughten/UaMITgcm/tree/master/example/WSFRIS_999](https://github.com/knaughten/UaMITgcm/tree/master/example/WSFRIS_999)

(Kaitlin's advice is to take the EXF configuration from FRIS999 and everything else from WFRIS999)

The steps below are based on those in Kaitlin Naughten's wiki associated with her python package: 

[https://github.com/knaughten/mitgcm_python/wiki/Creating-a-new-MITgcm-domain](https://github.com/knaughten/mitgcm_python/wiki/Creating-a-new-MITgcm-domain)

# Install mitgcm_python

The mitgcm_python package is a toolkit for constructing model setups in MITgcm. On BAS HPC, I first navigated into a suitable directory on the Expose drive. Next, I cloned a fresh copy of MITgcm and mitgcm_python:

```
git clone https://github.com/mitgcm/mitgcm
git clone https://github.com/knaughten/mitgcm_python
```
Next, since I'm using tsch, I use this command to set a required environment variable:

```
setenv PYTHONPATH (path_to_mitgcm)/MITgcm/utils/python/MITgcmutils
```

Note that this environment variable is only set for a single terminal session. One could add it to a startup script, if desired. At present, mitgcm_python is written in Python 2, so I had to switch modules. I also loaded NetCDF for I/O:

```
module swap python/conda3 python/conda-python-2.7.14
module load netcdf
```

Finally, I entered the command `python` and imported the packages:

```
import mitgcm_python
import MITgcmutils
```

There were no error messages, which is a good sign. 

# Establish the grid and bathymetry

## Define lat-lon points
Next, we can define the grid using the 'latlon_points' function as follows. Import some specific utilities:
```
from mitgcm_python.make_domain import *
```
For the SO-WISE (gyre) grid, we will try this initial configuration:
```
lon, lat = latlon_points(-85, 90, -84.2, -30, 0.25, 'topo_outputs/delY')
```
Which produces the following:
```
Northern boundary moved to -29.9313968126
Writing delY

Changes to make to input/data:
xgOrigin=275
ygOrigin=-84.2
dxSpacing=0.25
delYfile='delY' (and copy this file into input/)

Nx = 700 which has the factors [1, 2, 4, 5, 7, 10, 14, 20, 25, 28, 35, 50, 70, 100, 140, 175, 350, 700]
Ny = 558 which has the factors [1, 2, 3, 6, 9, 18, 31, 62, 93, 186, 279, 558]
If you are happy with this, proceed with interp_bedmap2. At some point, choose your tile size based on the factors and update code/SIZE.h.
Otherwise, tweak the boundaries and try again.
```
We typically want tiles in the 15-30 range, so we may experiment with the following configurations:
```
Nx = {20, 25, 28}
Ny = {18, 31}
```
Which puts the number of cores between 360 and 868. On ARCHER2, there are 128 cores per node, and 16 cores per NUMA region. We can ask Mike Mineter for expert advice on how to distribute the tiles across the compute nodes. 

## Interpolate BEDMAP2 and GEBCO bathymetry
Next, we'll create the bathymetry file using the interp_bedmap2 tool. For now, we won't include the optional bathymetry corrections or grounded icebergs. These can be added later if needed. First, create a bathymetric input directory and link to the required files:
```
mkdir topo_inputs
cd topo_inputs
ln -s /data/oceans_input/raw_input_data/bedmap2/bedmap2_bin/* .
ln -s /data/oceans_input/raw_input_data/GEBCO/GEBCO_2014_2D.nc .
cd ..
mkdir topo_outputs
mv delY topo_outputs
```
Next, in python, set some variables, and call `interp_bedmap2`:
```
topo_dir='topo_inputs'
nc_outfile='topo_outputs/sowise_gyre_bathy.nc'
interp_bedmap2(lon, lat, topo_dir, nc_outfile)
```
This will make a combined BEDMAP2/GEBCO bathymetry file. Here is some of the output from this function:
```
The results have been written into topo_outputs/sowise_gyre_bathy.nc
Take a look at this file and make whatever edits you would like to the mask (eg removing everything west of the peninsula; you can use edit_mask if you like). Then set your vertical layer thicknesses in a plain-text file, one value per line (make sure they clear the deepest bathymetry of 7933.9877905 m), and run remove_grid_problems
```
We shouldn't need to clear any deeper than 6000 m. This will have at least some representation of the South Sandwich Trench, without trying to represent the entirety of it. 

## Edit land mask
We can make some manual edits to the mask at this point. For simplicity, we can fill out everything  north of 45°S west of 70°W. This part of the Pacific Ocean can be ignored for this application (although pay attention to it later; it may cause some problems down the line). In the file `make_domain.py`, I added the following key:
```
    elif key == 'GYRE':
        # SO-WISE (gyre configuration)
        # Block out everything west of South America [xmin, xmax, ymin, ymax]
        omask = mask_box(omask, lon_2d, lat_2d, xmin=-85.0, xmax=-70.0, ymin=-50, ymax=-30)
        # Fill everything deeper than 6000 m
        bathy[bathy<-6000] = -6000
```
(Update: I've submitted a pull request to get this into the main mitgcm_python). I then ran the following command:
```
edit_mask('topo_outputs/sowise_gyre_bathy.nc', 'topo_outputs/sowise_gyre_bathy_edited.nc', key='SO-WISE-GYRE')
```
However, it seems like this didn't actually do anything. The ocean mask and bathymetry are unchanged. 

## Choose vertical layer thickness
At present, this must be done manually. We have to list the grid cell thicknesses in a plain text file, separated by commas. Here are the suggested values from Kaitlin's FRIS999 run, with a few more large levels added to capture the trench (that really may not be needed; I'm just trying it for now). Here is some Matlab code to generate the vertical levels, with a smooth factor of 1.031 throughout the water column.

```
% Select number of vertical levels
Nz = 120;   

% Define upper cell thickness, generate the rest
delR_gradual(1) = 5.;
for n=2:Nz
    delR_gradual(n) = 1.031*delR_gradual(n-1); %#ok<*SAGROW>
end

delR_gradual = round(delR_gradual,1);
disp(delR_gradual')
sum(delR_gradual)

```
Examining these in Matlab, I see that they total up to 6129.10m, which is about right. However, this is a massive 120 vertical levels! That's quite a lot, but we do need lots of levels to capture what's going on under the ice shelf cavities.

## Filling, digging, and zapping grid problems
Next, let's run this command to take care of some ocean/ice grid issues:
```
remove_grid_problems(nc_infile, nc_outfile, dz_file, hFacMin=hFacMin, hFacMinDr=hFacMinDr)
```
Specifically, I ran the following command with explicit paths:
```
remove_grid_problems('topo_outputs/sowise_gyre_bathy_edited.nc','topo_outputs/sowise_gyre_bathy_fixed.nc','topo_outputs/dz_file.txt',hFacMin=0.1, hFacMinDr=20.)
```
The script fills and zaps various grid cells; here is the output:
```
Filling isolated bottom cells
...8799 cells to fill
Digging subglacial lakes
...3949 cells to dig
Digging based on field to west
...1500 cells to dig
Digging based on field to east
...1320 cells to dig
Digging based on field to south
...1090 cells to dig
Digging based on field to north
...510 cells to dig
Zapping thin ice shelf draft
...1 cells to zap
```
## Write to binary
Now that I have the bathymetry set up, write out the binary files that include bathymetry and draft. 
```
write_topo_files(nc_file, bathy_file, draft_file)
```
Specifically,
```
write_topo_files('topo_outputs/sowise_gyre_bathy_fixed.nc', 'topo_outputs/bathy_gyre', 'topo_outputs/draft_gyre')
```
I've downloaded all the `topo_outputs` files to Dropbox for easy viewing, backup, and transfer. Now we can get started on the model setup files. 

# Create initial setup in MITgcm
First, I've cloned the MITgcm repository into an `MITgcm_sowise_dev` directory on ARCHER2 (using the early access account). Ideally, I would like to keep this state estimate machinery working with the latest version of the code. That being said, I'll note the time of cloning, which is 10 February 2021. Parallel to this, let's create a repository for the actual model setup files. I've decided to be deliberate about this, adding one file at a time to the new repository. 
```
git clone https://github.com/MITgcm/MITgcm.git
cd MITgcm
mkdir experiments
cd experiments
```
Next, we'll create the repository under "experiments". It will be separate from the MITgcm repository. The next steps include commands necessary to make contributions back to the so-wise-gyre repository on GitHub. The `clone` command creates a copy of the repository locally. The `remote add upstream` command adds the GitHub repository as the upstream for comparison. The `fetch` command ensures that the local copy is up-to-date. Finally, the `checkout` command creates a new branch. 
```
git clone https://github.com/so-wise/so-wise-gyre
git remote add upstream https://github.com/so-wise/so-wise-gyre
git fetch upstream
git checkout -b «YOUR_NEWBRANCH_NAME» 
```
In this case, we'll call the new branch `add-codemods`. Note that the instructions on the MITgcm website state that we should have put `upstream/master` after the new branch name, but this resulted in a fatal error. I'm not sure why. 

Once the edits, adds, and git commits are all done, we can push the changes back to GitHub:
```
git push -u origin «YOUR_NEWBRANCH_NAME»
```

### Questions
* Should we extend the domain even further east, such that the boundary is far from the gyre extent? 
