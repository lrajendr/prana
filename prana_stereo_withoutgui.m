%Running stereo PIV without Gui
%Please load or create calibration job, self cal job and prana2dprocessing
%job and then proceed
clear all;

%%% LOADING CALIBRATION JOB FILE
cal= input('Do you want to load a Calibration job? (Y/N):','s');
if strcmpi(cal,'Y')
    [f1,p1]=uigetfile('*.*','Load Calibration Job File');
    load([p1,f1]);
    caljob=datasave.caljob;
    clear datasave;
else
    prana_SPIV;
    fprintf('\n Setup and Load cal job \n');
    keyboard;
    [f1,p1]=uigetfile('*.*','Load Calibration Job File');
    load([p1,f1]);
    caljob=datasave.caljob;
    clear datasave;
end


%%%LOADING SELFCAL JOB FILE
selfcal= input('Do you want to load a Self-Calibration job? (Y/N):','s');
if strcmpi(selfcal,'Y')
    [f1,p1]=uigetfile('*.*','Load Self Calibration Job File');
    load([p1,f1]);
    selfcaljob=Data;
    clear Data;
else
    selfcalprana;
    fprintf('\n  Setup and Load Selfcal job \n');
    keyboard;
    [f1,p1]=uigetfile('*.*','Load Self Calibration Job File');
    load([p1,f1]);
    selfcaljob=Data;
    clear Data;
end


%%%LOADING PRANA JOB FILE
pranajob= input('Do you want to load a Prana job for twod processing? (Y/N):','s');
if strcmpi(pranajob,'Y')
    [f1,p1]=uigetfile('*.*','Load Prana Job File');
    load([p1,f1]);
    planarjob=Data;
    clear Data;
else
    prana;
    fprintf('\n  Setup and Load Selfcal job \n');
    keyboard;
    [f1,p1]=uigetfile('*.*','Load Prana Job File');
    load([p1,f1]);
    planarjob=Data;
    clear Data;
end

%%
%%%DOING CALIBRATION

allx1data(:,1)   = caljob.calibration_data.x_world_full{1};  % contains all x,y,z data for camera 1
allx1data(:,2)   = caljob.calibration_data.y_world_full{1};
allx1data(:,3)   = caljob.calibration_data.z_world_full{1};

allx2data(:,1)   = caljob.calibration_data.x_world_full{2};       % contains all x,y,z data for camera 2
allx2data(:,2)   = caljob.calibration_data.y_world_full{2};
allx2data(:,3)   = caljob.calibration_data.z_world_full{2};

allX1data(:,1)   = caljob.calibration_data.x_image_full{1};       % contains all X,Y data for camera 1
allX1data(:,2)   = caljob.calibration_data.y_image_full{1};

allX2data(:,1)   = caljob.calibration_data.x_image_full{2};
allX2data(:,2)   = caljob.calibration_data.y_image_full{2};

rA1=caljob.y_pixel_number;

allX1data(:,1)  = allX1data(:,1)-0.5;      % convert from image coords to regular coords ((0,0) at bottom left corner)
allX1data(:,2)  = rA1-allX1data(:,2)+0.5;
allX2data(:,1)  = allX2data(:,1)-0.5;      % convert from image coords to regular coords ((0,0) at bottom left corner)
allX2data(:,2)  = rA1-allX2data(:,2)+0.5;

modeltype   = caljob.modeltype;
optionsls   = caljob.optionsls;

caljob.allx1data=allx1data;
caljob.allx2data=allx2data;
caljob.allX1data=allX1data;
caljob.allX2data=allX2data;

[a_cam1, a_cam2, aXcam1, aYcam1, aXcam2, aYcam2, convergemessage] = fitmodels(allx1data,...
    allx2data,allX1data,allX2data,modeltype,optionsls);


caljob.aXcam1 = aXcam1;     % save the mapping coefficients
caljob.aYcam1 = aYcam1;
caljob.aXcam2 = aXcam2;
caljob.aYcam2 = aYcam2;
%[aXcam1 aYcam1 aXcam2 aYcam2]
caljob.a_cam1 = a_cam1;
caljob.a_cam2 = a_cam2;
 
caljob.convergemessage = convergemessage; 
%[caljob.aXcam1 caljob.aYcam1 caljob.aXcam2 caljob.aYcam2]

%%%DOING SELF CALIBRATION

caldata=caljob; %CREATING COPY OF CAL JOB SUCH THAT ORIGINAL CAN BE RETRIEVED EVEN AFTER SELF CALIBRATION
reftrue=1;
 while (reftrue~=0)
 
 [caldatamod]=selfcalibration_v1(caldata,selfcaljob);
 
 caldata.allx1data=caldatamod.allx1data;
 caldata.allx2data=caldatamod.allx2data;
 caldata.aXcam1=caldatamod.aXcam1;
 caldata.aYcam1=caldatamod.aYcam1;
 caldata.aXcam2=caldatamod.aXcam2;
 caldata.aYcam2=caldatamod.aYcam2;
 clear caldatamod;
 %[caldatamod]=selfcalibration_v1(caldata,selfcaljob);
 
  refine= input('Do you want to Refine? (Y/N):','s');
  
  if strcmpi(refine,'Y')
      reftrue=1;
  else
     reftrue=0;
  end
 
 end
% [caldata.aXcam1 caldata.aYcam1 caldata.aXcam2 caldata.aYcam2]
 %caljob=caldata; % Use this if you want to overwrite caljob with self
 %calibrated mapping function.
 
%%%TWO-D PROCESSING AND RECONSTRUCTION

rectype{1}='Willert';
%rectype{1}='';
rectype{2}='Soloff';
%rectype{2}='';


[outputdirlist,scaling]=stereoreconstruction(caldata,planarjob,rectype);

% stereorecdirlist=outputdirlist;
% scaling=scaling;




