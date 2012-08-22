function pranaprocessing(Data,I1,I2,maskname)
%% --- Read Formatted Parameters ---
%input/output directory
if ispc
    imbase=[Data.imdirec '\' Data.imbase];
    maskbase=[Data.maskdirec '\' Data.maskbase];
    pltdirec=[Data.outdirec '\'];
else
    imbase=[Data.imdirec '/' Data.imbase];
    maskbase=[Data.maskdirec '/' Data.maskbase];
    pltdirec=[Data.outdirec '/'];
end

if nargin<3
    I1 = str2double(Data.imfstart):str2double(Data.imfstep):str2double(Data.imfend);
    I2 = I1+str2double(Data.imcstep);
end

%processing mask
if strcmp(Data.masktype,'none')
    mask = 1+0*double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I1(1))]));
    maskname=[];
elseif strcmp(Data.masktype,'static')
    mask = double(imread(Data.staticmaskname));
    mask = flipud(mask);
    maskname=[];
elseif strcmp(Data.masktype,'dynamic')
%     if nargin<4
        maskfend=str2double(Data.imfstart)+str2double(Data.imfstep)*length(str2double(Data.imfstart):str2double(Data.imfstep):str2double(Data.imfend))-1;
        maskname=str2double(Data.imfstart):str2double(Data.imfstep):maskfend;
%     end
end

%method and passes
P = str2double(Data.passes);
Method = {'Multipass','Multigrid','Deform','Ensemble','EDeform','Multiframe'};
M = Method(str2double(Data.method));
% Color channel
try
    if isfield(Data,'channel')
        channel = str2double(Data.channel);
        if isnan(channel);
            fprintf('Color channel returned nan.  Please check color designation\n and confirm that it takes a value of a string.\n Setting color channel to ''red.''\n')
            channel = 1;
            Data.channel = '1';
        end
    else
        channel = 1;
        Data.channel = '1';
        fprintf('Could not find color channel information, using ''red'' (first channel) as default\n')
    end
catch ME
	fprintf('Unknown issure with color channel, trying ''red'' (first channel) as default\n%s',ME.stack(1))
    channel = 1;
    Data.channel = '1';
end

%algorithm options
Velinterp = str2double(Data.velinterp);
Iminterp  = str2double(Data.iminterp);
Nmax      = str2double(Data.framestep);
ds        = str2double(Data.PIVerror);

%physical parameters
Mag  = str2double(Data.wrmag);
dt   = str2double(Data.wrsep);
Freq = str2double(Data.wrsamp);
%checking to makesure physical parameters are infact numbers.
if isnan(Mag) || isnan(dt) || isnan(Freq)
    if isnan(Mag)    
    Mag = 1;
    fprintf('Magnifcation Value improporly set, changing the value to 1\n')
    end
    if isnan(dt)    
    dt = 1;
    fprintf('Pulse Separation improporly set, changing the value to 1\n')
    end
    if isnan(Freq)
    Freq = 1;
    fprintf('Sampling Rate improporly set, changing the value to 1\n')
    end
end

% %initialization
% Effective size of window after Gaussian filtering
Wres = zeros(2, 2, P);

% Size of unfiltered window (pixels)
Wsize = zeros(P,2);

% Grid resolution
Gres = zeros(P,2);

% NOT SURE

% Not Sure
Gbuf            = zeros(P,2);
Corr            = cell(P,1);  %correlation type on each pass
D               = zeros(P,2);
Zeromean        = zeros(P,1);
Peaklocator     = zeros(P,1);
Velsmoothswitch = zeros(P,1);
Velsmoothfilt   = zeros(P,1);
Valswitch       = zeros(P,1);
UODswitch       = zeros(P,1);
Bootswitch      = zeros(P,1);
Threshswitch    = zeros(P,1);
Writeswitch     = zeros(P,1);
Peakswitch      = zeros(P,1);
UODwinsize      = zeros(P,2);
UODthresh       = zeros(P,1);
Bootper         = zeros(P,1);
Bootiter        = zeros(P,1);
Bootkmax        = zeros(P,1);
Uthresh         = zeros(P,2);
Vthresh         = zeros(P,2);
extrapeaks      = zeros(P,1);
PeakNum         = zeros(P,1);
PeakMag         = zeros(P,1);
PeakVel         = zeros(P,1);
wbase           = cell(0);
frac_filt       = zeros(P,1);
mindefloop      = zeros(P,1); % variables for the deformation convergences
maxdefloop      = zeros(P,1);
condefloop      = zeros(P,1);
saveplane       = zeros(P,1);

%read data info for each pass
for e=1:P
    
    %create structure for pass "e"
    eval(['A = Data.PIV' num2str(e) ';']);
    
    %store bulk window offset info
    if e==1
        BWO=[str2double(A.BWO(1:(strfind(A.BWO,',')-1))) str2double(A.BWO((strfind(A.BWO,',')+1):end))];
    end
    
    % Window Resolution (eventually move the str2double commands to the GUI callback)
    winres_com = regexp(A.winres,'[,;]');
    if length(winres_com) > 1%isfield(A,'winres1')
    %  Window resolutions for first image in correlation pair
    xwin_im1 = str2double(A.winres(1:winres_com(1)-1));
    ywin_im1 = str2double(A.winres(winres_com(1) + 1:winres_com(2)-1));
    
    %  Window resolutions for second image in correlation pair
    xwin_im2 = str2double(A.winres(winres_com(2)+1:winres_com(3)-1));
    ywin_im2 = str2double(A.winres(winres_com(3)+1:end));
    else
    xwin_im1 = str2double(A.winres(1:winres_com(1)-1));
    ywin_im1 = str2double(A.winres(winres_com(1)+1:end));
    xwin_im2 = xwin_im1;
    ywin_im2 = ywin_im1;
    end

%     Window resolution matrix
    Wres(:,:, e) = [xwin_im1 ywin_im1; xwin_im2 ywin_im2];
    
%     Window size and grid resolution 
    Wsize(e,:) = [str2double(A.winsize(1:(strfind(A.winsize,',')-1))) str2double(A.winsize((strfind(A.winsize,',')+1):end))];
    Gres(e,:) = [str2double(A.gridres(1:(strfind(A.gridres,',')-1))) str2double(A.gridres((strfind(A.gridres,',')+1):end))];
    Gbuf(e,:) = [str2double(A.gridbuf(1:(strfind(A.gridbuf,',')-1))) str2double(A.gridbuf((strfind(A.gridbuf,',')+1):end))];
    Corr{e} = A.corr; %why do we subtract 1 from A.corr?  Just to make things more confusing? (SCC,RPC,GCC,FWC,SPC)
    D(e,:) = [str2double(A.RPCd(1:(strfind(A.RPCd,',')-1))) str2double(A.RPCd((strfind(A.RPCd,',')+1):end))];
    frac_filt(e) = str2double(A.frac_filt);
    Zeromean(e) = str2double(A.zeromean);
    Peaklocator(e) = str2double(A.peaklocator);
    Velsmoothswitch(e) = str2double(A.velsmooth);
    Velsmoothfilt(e) = str2double(A.velsmoothfilt);
    mindefloop(e) = str2double(A.deform_min);
    maxdefloop(e) = str2double(A.deform_max);
    condefloop(e) = str2double(A.deform_conv);
    
    if any(Wres(1,:,e)>Wsize(e,:)) || any(Wres(2,:,e)>Wsize(e,:))
        warning('warning:ResGraterThenSize','Pass %0.0f has a window resolution larger then the windown size!\n   [%0.0f,%0.0f;%0.0f %0.0f] > [%0.0f,%0.0f]\n',e,Wres(1,1,e),Wres(1,2,e),Wres(2,1,e),Wres(2,2,e),Wsize(e,1), Wsize(e,2))
    end
    
    %validation and thresholding
    Valswitch(e)=str2double(A.val);
    UODswitch(e)=str2double(A.uod);
    Bootswitch(e)=str2double(A.bootstrap);
    Threshswitch(e)=str2double(A.thresh);
    Writeswitch(e)=str2double(A.write);

    vpass=[0 strfind(A.uod_window,';') length(A.uod_window)+1];
    for q=1:(length(vpass)-1)
        B=A.uod_window((vpass(q)+1):(vpass(q+1)-1));
        UODwinsize(e,:,q)=[str2double(B(1:(strfind(B,',')-1))) str2double(B((strfind(B,',')+1):end))];
        UODthresh(e,q)=str2double(A.uod_thresh(1+2*(q-1)));
    end
    
    Bootper(e)=str2double(A.bootstrap_percentsampled);
    Bootiter(e)=str2double(A.bootstrap_iterations);
    Bootkmax(e)=str2double(A.bootstrap_passes);
    
    if str2double(A.thresh)==1
        Uthresh(e,:)=[str2double(A.valuthresh(1:(strfind(A.valuthresh,',')-1))) str2double(A.valuthresh((strfind(A.valuthresh,',')+1):end))];
        Vthresh(e,:)=[str2double(A.valvthresh(1:(strfind(A.valvthresh,',')-1))) str2double(A.valvthresh((strfind(A.valvthresh,',')+1):end))];
    else
        Uthresh(e,:)=[-inf,inf];
        Vthresh(e,:)=[-inf,inf];
    end
    
    extrapeaks(e)=str2double(A.valextrapeaks);

    %peak information
    Peakswitch(e)=str2double(A.savepeakinfo);
    PeakNum(e)=str2double(A.corrpeaknum);
    PeakMag(e)=str2double(A.savepeakmag);
    PeakVel(e)=str2double(A.savepeakvel);
    saveplane(e) = str2double(A.saveplane);
    
    %output directory
    wbase(e,:)={A.outbase};
    
end
wbase_org=wbase;

%% --- Evaluate Image Sequence ---
switch char(M)
    
    case {'Multipass','Multigrid','Deform'}
        %% --- Multipass, Multigrid, Deform
        frametime=zeros(length(I1),1);
        for q=1:length(I1)
            
            tf=tic;
            frametitle=['Frame' sprintf(['%0.' Data.imzeros 'i'],I1(q)) ' and Frame' sprintf(['%0.' Data.imzeros 'i'],I2(q))];

            %load image pair and flip coordinates
            im1 = double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I1(q))]));
            im2 = double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I2(q))]));
            
            % Specify which color channel(s) to consider
            % This was changed to greater then 2 because John had images
            % that were 4 channel with the last channel being a
            % transparency channel.
            if size(im1, 3) > 2
                %Extract only red channel
                 if channel == 1;
                    im1 = im1(:,:,1);
                    im2 = im2(:,:,1);
                %Extract only green channel
                 elseif channel == 2;
                    im1 = im1(:,:,2);
                    im2 = im2(:,:,2);
                %Extract only blue channel
                 elseif channel == 3;
                    im1 = im1(:,:,3);
                    im2 = im2(:,:,3);
                %Weighted average of channels (see rgb2gray for
                %explanation of weighting factors)
                 elseif channel == 4;
                    im1 = 0.2989 * im1(:, :, 1) + 0.5870 * im1(:, :, 2) + 0.1140 * im1(:, :, 3);
                    im2 = 0.2989 * im2(:, :, 1) + 0.5870 * im2(:, :, 2) + 0.1140 * im2(:, :, 3);
                %Evenly weighted mean of channels
                 elseif channel == 5;
                    im1 = (im1(:,:,1) + im1(:,:,2) + im1(:,:,3))/3;
                    im2 = (im2(:,:,1) + im2(:,:,2) + im2(:,:,3))/3;
                %ensemble correlation of channels 
                 elseif channel == 6;
                     im1=im1(:,:,1:3);
                     im2=im2(:,:,1:3);
                 end

             else
            %	Take only red channel
                im1 =im1(:,:,1);
                im2 =im2(:,:,1);
                channel = 1;
             end

            %  Flip images
            %flipud only works on 2D matices.  What about flipdim(im1,1) instead?
            im1 = im1(end:-1:1,:,:);%flipud(im1);
            im2 = im2(end:-1:1,:,:);%flipud(im2);

            %   Determine size of images          
            L = size(im1);
            
            %load dynamic mask and flip coordinates
            if strcmp(Data.masktype,'dynamic')
                mask = double(imread([maskbase sprintf(['%0.' Data.maskzeros 'i.' Data.maskext],maskname(q))]));
                mask = flipud(mask);
            end

            %initialize grid and evaluation matrix
            [XI,YI]=IMgrid(L,[0 0]);

            UI = BWO(1)*ones(size(XI));
            VI = BWO(2)*ones(size(YI));
            
            % Preallocating variables
            corrtime=zeros(P,max(maxdefloop));
            valtime=zeros(P,max(maxdefloop));
            savetime=zeros(P,1);
            interptime=zeros(P,max(maxdefloop));
            deformtime=zeros(P,max(maxdefloop));
            defconvU = zeros(P,max(maxdefloop));
            defconvV = zeros(P,max(maxdefloop));
            
            e = 0; defloop = 1;
            % This while statment is used to interatively move through the
            % deformations.  If the minimum number of loops hasn't been
            % reach it will keep iterating otherwise it should stop.
            while (e<P && defloop == 1) || (e<=P && defloop~=1)%for e=1:P
                if defloop == 1
                    e=e+1;
                end
                
                t1=tic;
                [X,Y]=IMgrid(L,Gres(e,:),Gbuf(e,:));
                S=size(X);X=X(:);Y=Y(:);
                
                if strcmp(M,'Multipass')
                    Ub=UI(:);
                    Vb=VI(:);
                else
                    Ub = reshape(downsample(downsample( UI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
                    Vb = reshape(downsample(downsample( VI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
                end
                Eval=reshape(downsample(downsample( mask(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
                Eval(Eval==0)=-1;
                Eval(Eval>0)=0;

                %correlate image pair
                if (e~=1 || defloop~=1) && strcmp(M,'Deform')         %then don't offset windows, images already deformed
                    %if Corr(e)<4
                    if ~strcmpi(Corr{e},'SPC')
                        [Xc,Yc,Uc,Vc,Cc,Dc,Cp]=PIVwindowed(im1d,im2d,Corr{e},Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),Peaklocator(e),Peakswitch(e) || (Valswitch(e) && extrapeaks(e)),frac_filt(e),saveplane(e),X(Eval>=0),Y(Eval>=0));
                        if Peakswitch(e) || (Valswitch(e) && extrapeaks(e))
                            Uc = Uc + repmat(Ub(Eval>=0),[1 3]);   %reincorporate deformation as velocity for next pass
                            Vc = Vc + repmat(Vb(Eval>=0),[1 3]);
                        else
                            Uc = Uc + Ub(Eval>=0);   %reincorporate deformation as velocity for next pass
                            Vc = Vc + Vb(Eval>=0);
                        end
                    else
                        [Xc,Yc,Uc,Vc,Cc]=PIVphasecorr(im1d,im2d,Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),Peakswitch(e),X(Eval>=0),Y(Eval>=0));
                        %Sam deleted the Cc output from PIVPhaseCorr - why?  because we don't use it? But it's needed for Dc in next line?
                        %[Xc,Yc,Uc,Vc]=PIVphasecorr(im1d,im2d,Wsize(e,:),Wres(:, :, e),0,D(e),Zeromean(e),Peakswitch(e),X(Eval>=0),Y(Eval>=0));
                        Dc = zeros(size(Cc));
 
                        Uc = Uc + Ub(Eval>=0);   %reincorporate deformation as velocity for next pass
                        Vc = Vc + Vb(Eval>=0);
                    end
                    
                else                                    %either first pass, or not deform
                    if ~strcmpi(Corr{e},'SPC')
                        if any(isnan(Ub(Eval>=0)))
                            keyboard
                        end
                        [Xc,Yc,Uc,Vc,Cc,Dc,Cp]=PIVwindowed(im1,im2,Corr{e},Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),Peaklocator(e),Peakswitch(e) || (Valswitch(e) && extrapeaks(e)),frac_filt(e),saveplane(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0));
                    else
                        [Xc,Yc,Uc,Vc,Cc]=PIVphasecorr(im1,im2,Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),Peakswitch(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0));
                        Dc = zeros(size(Cc));
                    end
                end

                if ~strcmpi(Corr{e},'SPC') %SPC=4
                    if Peakswitch(e) || (Valswitch(e) && extrapeaks(e))
                        U=zeros(size(X,1),3);
                        V=zeros(size(X,1),3);
                        U(repmat(Eval>=0,[1 3]))=Uc;V(repmat(Eval>=0,[1 3]))=Vc;
                        C=zeros(size(X,1),3);
                        Di=zeros(size(X,1),3);
                        C(repmat(Eval>=0,[1 3]))=Cc;
                        Di(repmat(Eval>=0,[1 3]))=Dc;
                    else
                        U=zeros(size(X));V=zeros(size(X));C=[];Di=[];
                        U(Eval>=0)=Uc;V(Eval>=0)=Vc;
                    end
                else
                    U=zeros(size(X));V=zeros(size(X));
                    U(Eval>=0)=Uc;V(Eval>=0)=Vc;
                    if Peakswitch(e)
                        C=zeros(size(X,1),3);
                        Di=zeros(size(X,1),3);
                        C(repmat(Eval>=0,[1 3]))=Cc;
                        Di(repmat(Eval>=0,[1 3]))=Dc;
                        
                    else 
                        C=[];
                        Di=[];
                    end
                end
                
                corrtime(e,defloop)=toc(t1);

                %validation
                if Valswitch(e)
                    t1=tic;
                    
                    [Uval,Vval,Evalval,Cval,Dval]=VAL(X,Y,U,V,Eval,C,Di,Threshswitch(e),UODswitch(e),Bootswitch(e),extrapeaks(e),...
                        Uthresh(e,:),Vthresh(e,:),UODwinsize(e,:,:),UODthresh(e,UODthresh(e,:)~=0)',Bootper(e),Bootiter(e),Bootkmax(e));
                    
                    valtime(e,defloop)=toc(t1);
                else
                    Uval=U(:,1);Vval=V(:,1);Evalval=Eval(:,1);
                    if ~isempty(C)
                        Cval=C(:,1);
                        Dval=Di(:,1);
                    else
                        Cval=[];
                        Dval=[];
                    end
                end
                
                % --- Iterative Deformation Check ---
                % This block checks too see if the deformation has
                % converged or reach is max number of iterations.
                if strcmpi(M,'Deform')
                    if defloop == 1
                        Ud = Uval; Vd = Vval;
                    else
                        defconvU(e,defloop) = norm(Uval - Ud,2);
                        defconvV(e,defloop) = norm(Vval - Vd,2);
                        Ud = Uval; Vd = Vval;
                    end
                    if defloop == maxdefloop(e) || (defloop ~= 1 && defloop >= mindefloop(e) && defconvU(e,defloop) <= condefloop(e) && defconvV(e,defloop) <= condefloop(e))
                        if maxdefloop(e) ~= 1
                            % append the 'deform' and the pass number to
                            % the end of the file once the final number of
                            % iterations has been reached.
                            wbase{e,:} = sprintf([wbase_org{e,:} 'deform' num2str(defloop) '_']);
                        end
                        defloop = 1;
                    else
                        defloop = defloop+1;
                    end
                end

                %write output
                if Writeswitch(e) && defloop == 1
                    t1=tic;
                    
                    %SPC only returns 1 peak right now?
                    if Peakswitch(e)
                        if PeakVel(e) && ~strcmpi(Corr{e},'SPC')
                            U=[Uval,U(:,1:PeakNum(e))];
                            V=[Vval,V(:,1:PeakNum(e))];
                        else
                            U=Uval; V=Vval;
                        end
                        if PeakMag(e)
                            C=[Cval,C(:,1:PeakNum(e))];
                            Di=[Dval,Di(:,1:PeakNum(e))];
                        else
                            C=Cval;
                            Di=Dval;
                        end
                    else
                        U=Uval; V=Vval; C=Cval; Di=Dval;
                    end
                    Eval=Evalval;

                    %convert to physical units
                    Xval=X;Yval=Y;
                    X=X*Mag;Y=Y*Mag;
                    U=U*Mag/dt;V=V*Mag/dt;

                    %convert to matrix if necessary
                    if size(X,2)==1
                        [X,Y,U,V,Eval,C,Di]=matrixform(X,Y,U,V,Eval,C,Di);
                    end

                    %remove nans from data, replace with zeros
                    U(Eval<0|isinf(U))=0;V(Eval<0|isinf(V))=0;
                    
                    if str2double(Data.datout)
                        time=I1(q)/Freq;
                        write_dat_val_C([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.dat' ],I1(q))],X,Y,U,V,Eval,C,Di,e,time,char(wbase(e,:)));
                    end
                    
                    if str2double(Data.multiplematout)
                        save([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.mat' ],I1(q))],'X','Y','U','V','Eval','C','Di')
                    end
                    % This saves the correlation planes if that selection
                    % has been made in the job file.
                    if saveplane(e) && ~strcmpi(Corr{e},'SPC')
                        Xloc = Xc;Yloc=Yc;C_planes=Cp;%#ok
                        save(sprintf(['%s%scorrplanes_%0.' Data.imzeros 'i.mat' ],pltdirec,wbase{e,:},I1(q)),'Xloc','Yloc','C_planes')
                        clear Xloc Yloc C_planes
                    end
                    
                    X=Xval;Y=Yval;
                    
                    savetime(e,defloop)=toc(t1);
                end
                U=Uval; V=Vval;

                if e~=P || (strcmpi(M,'Deform') && defloop ~=1)
                    %reshape from list of grid points to matrix
                    X=reshape(X,[S(1),S(2)]);
                    Y=reshape(Y,[S(1),S(2)]);
                    U=reshape(U(:,1),[S(1),S(2)]);
                    V=reshape(V(:,1),[S(1),S(2)]);
                    
                    if strcmp(M,'Multigrid') || strcmp(M,'Deform')
                        t1=tic;

                        %velocity smoothing
                        if Velsmoothswitch(e)==1
                            [U,V]=VELfilt(U,V,UODwinsize(e,:,:),Velsmoothfilt(e));
                        end

                        %velocity interpolation
                        UI = VFinterp(X,Y,U,XI,YI,Velinterp);
                        VI = VFinterp(X,Y,V,XI,YI,Velinterp);

                        if defloop == 1
                            interptime(e+1,defloop)=toc(t1);
                        else
                            interptime(e,defloop)=toc(t1);
                        end
                        
                        if strcmp(M,'Deform')
                            t1=tic;
                            
                            %translate pixel locations
                            XD1 = XI+UI/2;
                            YD1 = YI+VI/2;
                            XD2 = XI-UI/2;
                            YD2 = YI-VI/2;

                            %preallocate deformed images
                            im1d = zeros(L);
                            im2d = zeros(L);

                            %cardinal function interpolation
                            if Iminterp==1
                                for i=1:L(1)
                                    for j=1:L(2)

                                        %image 1 interpolation
                                        nmin=max([1 (round(YD1(i,j))-3)]);
                                        nmax=min([L(1) (round(YD1(i,j))+3)]);
                                        mmin=max([1 (round(XD1(i,j))-3)]);
                                        mmax=min([L(2) (round(XD1(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD1(i,j)))*sin(pi*(n-YD1(i,j)))/(pi^2*(m-XD1(i,j))*(n-YD1(i,j)));
                                                if channel ~= 6
                                                    im1d(n,m)=im1d(n,m)+im1(i,j)*wi;
                                                else
                                                    im1d(n,m,:)=im1d(n,m,:)+im1(i,j,:)*wi;
                                                end
                                            end
                                        end

                                        %image 2 interpolation
                                        nmin=max([1 (round(YD2(i,j))-3)]);
                                        nmax=min([L(1) (round(YD2(i,j))+3)]);
                                        mmin=max([1 (round(XD2(i,j))-3)]);
                                        mmax=min([L(2) (round(XD2(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD2(i,j)))*sin(pi*(n-YD2(i,j)))/(pi^2*(m-XD2(i,j))*(n-YD2(i,j)));
                                                if channel ~= 6
                                                    im2d(n,m)=im2d(n,m)+im2(i,j)*wi;
                                                else
                                                    im2d(n,m,:)=im2d(n,m,:)+im2(i,j,:)*wi;
                                                end
                                            end
                                        end

                                    end
                                end

                            %cardinal function interpolation with Blackman filter
                            elseif Iminterp==2

                                for i=1:L(1)
                                    for j=1:L(2)

                                        %image 1 interpolation
                                        nmin=max([1 (round(YD1(i,j))-3)]);
                                        nmax=min([L(1) (round(YD1(i,j))+3)]);
                                        mmin=max([1 (round(XD1(i,j))-3)]);
                                        mmax=min([L(2) (round(XD1(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD1(i,j)))*sin(pi*(n-YD1(i,j)))/(pi^2*(m-XD1(i,j))*(n-YD1(i,j)));
                                                bi = (0.42+0.5*cos(pi*(m-XD1(i,j))/3)+0.08*cos(2*pi*(m-XD1(i,j))/3))*(0.42+0.5*cos(pi*(n-YD1(i,j))/3)+0.08*cos(2*pi*(n-YD1(i,j))/3));
                                                if channel ~= 6
                                                    im1d(n,m)=im1d(n,m)+im1(i,j)*wi*bi;
                                                else
                                                    im1d(n,m,:)=im1d(n,m,:)+im1(i,j,:)*wi*bi;
                                                end
                                            end
                                        end

                                        %image 2 interpolation
                                        nmin=max([1 (round(YD2(i,j))-3)]);
                                        nmax=min([L(1) (round(YD2(i,j))+3)]);
                                        mmin=max([1 (round(XD2(i,j))-3)]);
                                        mmax=min([L(2) (round(XD2(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD2(i,j)))*sin(pi*(n-YD2(i,j)))/(pi^2*(m-XD2(i,j))*(n-YD2(i,j)));
                                                bi = (0.42+0.5*cos(pi*(m-XD2(i,j))/3)+0.08*cos(2*pi*(m-XD2(i,j))/3))*(0.42+0.5*cos(pi*(n-YD2(i,j))/3)+0.08*cos(2*pi*(n-YD2(i,j))/3));
                                                if channel ~= 6
                                                    im2d(n,m)=im2d(n,m)+im2(i,j)*wi*bi;
                                                else
                                                    im2d(n,m,:)=im2d(n,m,:)+im2(i,j,:)*wi*bi;
                                                end
                                            end
                                        end

                                    end
                                end

                            end

                            %clip lower values of deformed images
                            im1d(im1d<0)=0; im1d(isnan(im1d))=0;
                            im2d(im2d<0)=0; im2d(isnan(im2d))=0;

                            %JJC: don't want to do this, should deform windows from start each time
                            % im1=im1d; im2=im2d;
                            
%                             keyboard
%                             figure(1),imagesc(im1),colormap(gray),axis image xy,xlabel('im1')
%                             figure(2),imagesc(im2),colormap(gray),axis image xy,xlabel('im2')
%                             figure(3),imagesc(im1d),colormap(gray),axis image xy,xlabel('im1d')
%                             figure(4),imagesc(im2d),colormap(gray),axis image xy,xlabel('im2d')
%                             pause
%                             imwrite(uint8(im1d),[pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'ia.png' ],I1(q))]);
%                             imwrite(uint8(im2d),[pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'ib.png' ],I1(q))]);
                            
                            if defloop == 1
                                deformtime(e+1,defloop)=toc(t1);
                            else
                                deformtime(e,defloop)=toc(t1);
                            end
                                
                        end
                    else
                        UI=U;VI=V;
                    end
                end
            end

            eltime=toc(tf);
            %output text
            fprintf('\n----------------------------------------------------\n')
            fprintf(['Job: ',Data.batchname,'\n'])
            fprintf([frametitle ' Completed (' num2str(q) '/' num2str(length(I1)) ') at %s \n'], datestr(now));
            fprintf('----------------------------------------------------\n')
            for e=1:P
                fprintf('correlation...                   %0.2i:%0.2i.%0.0f\n',floor(sum(corrtime(e,:))/60),floor(rem(sum(corrtime(e,:)),60)),rem(sum(corrtime(e,:)),60)-floor(rem(sum(corrtime(e,:)),60)))
                if Valswitch(e)
                    fprintf('validation...                    %0.2i:%0.2i.%0.0f\n',floor(sum(valtime(e,:))/60),floor(rem(sum(valtime(e,:)),60)),rem(sum(valtime(e,:)),60)-floor(rem(sum(valtime(e,:)),60)))
                end
                if strcmpi(M,'Deform') && mindefloop(e) ~= 1
                    fprintf('velocity interpolation...        %0.2i:%0.2i.%0.0f\n',floor(sum(interptime(e,:))/60),floor(rem(sum(interptime(e,:)),60)),rem(sum(interptime(e,:)),60)-floor(rem(sum(interptime(e,:)),60)))
                    fprintf('image deformation...             %0.2i:%0.2i.%0.0f\n',floor(sum(deformtime(e,:))/60),floor(rem(sum(deformtime(e,:)),60)),rem(sum(deformtime(e,:)),60)-floor(rem(sum(deformtime(e,:)),60)))
                end
                if Writeswitch(e)
                    fprintf('save time...                     %0.2i:%0.2i.%0.0f\n',floor(savetime(e)/60),floor(rem(savetime(e),60)),rem(savetime(e),60)-floor(rem(savetime(e),60)))
                end
                if strcmp(M,'Multigrid') || (strcmp(M,'Deform') && mindefloop(e) == 1)
                    if e~=P
                        fprintf('velocity interpolation...        %0.2i:%0.2i.%0.0f\n',floor(sum(interptime(e,:))/60),floor(rem(sum(interptime(e,:)),60)),rem(sum(interptime(e,:)),60)-floor(rem(sum(interptime(e,:)),60)))
                        if strcmp(M,'Deform')
                            fprintf('image deformation...             %0.2i:%0.2i.%0.0f\n',floor(sum(deformtime(e,:))/60),floor(rem(sum(deformtime(e,:)),60)),rem(sum(deformtime(e,:)),60)-floor(rem(sum(deformtime(e,:)),60)))
                        end
                    end
                end
            end
            fprintf('total frame time...              %0.2i:%0.2i.%0.0f\n',floor(eltime/60),floor(rem(eltime,60)),rem(eltime,60)-floor(rem(eltime,60)))
            frametime(q)=eltime;
            comptime=mean(frametime(1:q))*(length(I1)-q);
            fprintf('estimated job completion time... %0.2i:%0.2i:%0.2i\n\n',floor(comptime/3600),floor(rem(comptime,3600)/60),floor(rem(comptime,60)))
        end
        
    case {'Ensemble','EDeform'}
        %% --- Ensemble and Ensemble Deform --- 
        frametime=zeros(P,1);

        %initialize grid and evaluation matrix
        im1=double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I1(1))]));
        L=size(im1);
        L(3)=size(im1,3);
        [XI,YI]=IMgrid(L,[0 0]);
        UI = BWO(1)*ones(size(XI));
        VI = BWO(2)*ones(size(XI));
        
        defconvU = zeros(P,max(maxdefloop));
        defconvV = zeros(P,max(maxdefloop));
        
        e = 0; defloop = 1;
        % This while statment is used to interatively move through the
        % deformations.  If the minimum number of loops hasn't been
        % reach it will keep iterating otherwise it should stop.
        while (e<P && defloop == 1) || (e<=P && defloop~=1)%for e=1:P
            if defloop == 1
                e=e+1;
                        
                frametitle=['Frame' sprintf(['%0.' Data.imzeros 'i'],I1(1)) ' to Frame' sprintf(['%0.' Data.imzeros 'i'],I2(end))];
                fprintf('\n----------------------------------------------------\n')
                fprintf(['Job: ',Data.batchname,'\n'])
                fprintf([frametitle ' (Pass ' num2str(e) '/' num2str(P) ')\n'])
                fprintf('----------------------------------------------------\n')
            
            end
            tf=tic;
            
            [X,Y]=IMgrid(L,Gres(e,:),Gbuf(e,:));
            S=size(X);X=X(:);Y=Y(:);
            Ub = reshape(downsample(downsample( UI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
            Vb = reshape(downsample(downsample( VI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
            Eval=reshape(downsample(downsample( mask(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
            Eval(Eval==0)=-1;
            Eval(Eval>0)=0;

            if Peakswitch(e) || (Valswitch(e) && extrapeaks(e))
                U=zeros(size(X,1),3);
                V=zeros(size(X,1),3);
                C=zeros(size(X,1),3);
                Di=zeros(size(X,1),3);
            else
                U=zeros(size(X));V=zeros(size(X));C=[];Di=[];
            end

            if str2double(Data.par) && matlabpool('size')>1

                spmd
                    verstr=version('-release');
                    if str2double(verstr(1:4))>=2010
                        I1dist=getLocalPart(codistributed(I1,codistributor('1d',2)));
                        I2dist=getLocalPart(codistributed(I2,codistributor('1d',2)));
                    else
                        I1dist=localPart(codistributed(I1,codistributor('1d',2),'convert'));
                        I2dist=localPart(codistributed(I2,codistributor('1d',2),'convert'));
                    end
                    
                    for q=1:length(I1dist)
                        
                        %load image pair and flip coordinates
                        im1=double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I1dist(q))]));
                        im2=double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I2dist(q))]));
                        if size(im1, 3) > 2
                            %Extract only red channel
                            if channel == 1;
                                im1 = im1(:,:,1);
                                im2 = im2(:,:,1);
                                %Extract only green channel
                            elseif channel == 2;
                                im1 = im1(:,:,2);
                                im2 = im2(:,:,2);
                                %Extract only blue channel
                            elseif channel == 3;
                                im1 = im1(:,:,3);
                                im2 = im2(:,:,3);
                                %Weighted average of channels (see rgb2gray for
                                %explanation of weighting factors)
                            elseif channel == 4;
                                im1 = 0.2989 * im1(:, :, 1) + 0.5870 * im1(:, :, 2) + 0.1140 * im1(:, :, 3);
                                im2 = 0.2989 * im2(:, :, 1) + 0.5870 * im2(:, :, 2) + 0.1140 * im2(:, :, 3);
                                %Evenly weighted mean of channels
                            elseif channel == 5;
                                im1 = (im1(:,:,1) + im1(:,:,2) + im1(:,:,3))/3;
                                im2 = (im2(:,:,1) + im2(:,:,2) + im2(:,:,3))/3;
                                %ensemble correlation of channels
                            elseif channel == 6;
                                im1=im1(:,:,1:3);
                                im2=im2(:,:,1:3);
                            end
                        else
                            %Take only red channel
                            im1 =im1(:,:,1);
                            im2 =im2(:,:,1);
                            channel = 1;
                        end
                        
                        %  Flip images
                        %flipud only works on 2D matices.
                        % im1=flipud(im1(:,:,1));
                        % im2=flipud(im2(:,:,1));
                        im1 = im1(end:-1:1,:,:);
                        im2 = im2(end:-1:1,:,:);
                        % L=size(im1);
                        
                        % The deformation for ensemble must be done before
                        % the correlation unlike in the instantanious
                        % images where it is done after correlation
                        if strcmpi(M,'EDeform') && (e~=1 || defloop ~=1)
                            
                            t1=tic;
                            %translate pixel locations
                            XD1 = XI+UI/2;
                            YD1 = YI+VI/2;
                            XD2 = XI-UI/2;
                            YD2 = YI-VI/2;
                            
                            %preallocate deformed images
                            im1d = zeros(L);
                            im2d = zeros(L);
                            
                            %cardinal function interpolation
                            if Iminterp==1
                                for i=1:L(1)
                                    for j=1:L(2)
                                        
                                        %image 1 interpolation
                                        nmin=max([1    (round(YD1(i,j))-3)]);
                                        nmax=min([L(1) (round(YD1(i,j))+3)]);
                                        mmin=max([1    (round(XD1(i,j))-3)]);
                                        mmax=min([L(2) (round(XD1(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD1(i,j)))*sin(pi*(n-YD1(i,j)))/(pi^2*(m-XD1(i,j))*(n-YD1(i,j)));
                                                if channel ~=6 
                                                    im1d(n,m)=im1d(n,m)+im1(i,j)*wi;
                                                else
                                                    im1d(n,m,:)=im1d(n,m,:)+im1(i,j,:)*wi;
                                                end
                                            end
                                        end
                                        
                                        %image 2 interpolation
                                        nmin=max([1    (round(YD2(i,j))-3)]);
                                        nmax=min([L(1) (round(YD2(i,j))+3)]);
                                        mmin=max([1    (round(XD2(i,j))-3)]);
                                        mmax=min([L(2) (round(XD2(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD2(i,j)))*sin(pi*(n-YD2(i,j)))/(pi^2*(m-XD2(i,j))*(n-YD2(i,j)));
                                                if channel ~= 6
                                                    im2d(n,m)=im2d(n,m)+im2(i,j)*wi;
                                                else
                                                    im2d(n,m,:)=im2d(n,m,:)+im2(i,j,:)*wi;
                                                end
                                            end
                                            
                                        end
                                        
                                    end
                                end

                                %cardinal function interpolation with Blackman filter
                            elseif Iminterp==2
                                
                                for i=1:L(1)
                                    for j=1:L(2)
                                        
                                        %image 1 interpolation
                                        nmin=max([1    (round(YD1(i,j))-3)]);
                                        nmax=min([L(1) (round(YD1(i,j))+3)]);
                                        mmin=max([1    (round(XD1(i,j))-3)]);
                                        mmax=min([L(2) (round(XD1(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD1(i,j)))*sin(pi*(n-YD1(i,j)))/(pi^2*(m-XD1(i,j))*(n-YD1(i,j)));
                                                bi = (0.42+0.5*cos(pi*(m-XD1(i,j))/3)+0.08*cos(2*pi*(m-XD1(i,j))/3))*(0.42+0.5*cos(pi*(n-YD1(i,j))/3)+0.08*cos(2*pi*(n-YD1(i,j))/3));
                                                if channel ~= 6
                                                    im1d(n,m)=im1d(n,m)+im1(i,j)*wi*bi;
                                                else
                                                    im1d(n,m,:)=im1d(n,m,:)+im1(i,j,:)*wi*bi;
                                                end
                                            end
                                        end
                                        
                                        %image 2 interpolation
                                        nmin=max([1    (round(YD2(i,j))-3)]);
                                        nmax=min([L(1) (round(YD2(i,j))+3)]);
                                        mmin=max([1    (round(XD2(i,j))-3)]);
                                        mmax=min([L(2) (round(XD2(i,j))+3)]);
                                        for n=nmin:nmax
                                            for m=mmin:mmax
                                                wi = sin(pi*(m-XD2(i,j)))*sin(pi*(n-YD2(i,j)))/(pi^2*(m-XD2(i,j))*(n-YD2(i,j)));
                                                bi = (0.42+0.5*cos(pi*(m-XD2(i,j))/3)+0.08*cos(2*pi*(m-XD2(i,j))/3))*(0.42+0.5*cos(pi*(n-YD2(i,j))/3)+0.08*cos(2*pi*(n-YD2(i,j))/3));
                                                if channel ~= 6
                                                    im2d(n,m)=im2d(n,m)+im2(i,j)*wi*bi;
                                                else
                                                    im2d(n,m,:)=im2d(n,m,:)+im2(i,j,:)*wi*bi;
                                                end
                                            end
                                        end
                                        
                                    end
                                end
                                
                            end
                        
                            %clip lower values of deformed images
                            im1d(im1d<0)=0; im1d(isnan(im1d))=0;
                            im2d(im2d<0)=0; im2d(isnan(im2d))=0;
                        
                            deformtime=toc(t1);
                        end
                        
                        t1=tic;
                        %correlate image pair and average correlations
%                      [Xc,Yc,CC]=PIVensemble(im1,im2,Corr(e),Wsize(e,:),Wres(e, :, :),0,D(e),Zeromean(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0));
                        if strcmpi(M,'EDeform') && (e~=1 || defloop ~=1)
                            [Xc,Yc,CC]=PIVensemble(im1d,im2d,Corr{e},Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),frac_filt(e),X(Eval>=0),Y(Eval>=0));
                        else
                            [Xc,Yc,CC]=PIVensemble(im1,im2,Corr{e},Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),frac_filt(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0));
                        end
                    
                        if ~strcmpi(Corr{e},'SPC')
                            if q==1
                                CCmdist=CC;
                                %cnvg_est = 0;
                                CC = []; %#ok% This clear is required for fine grids or big windows
                            else
                                % % cnvg_est = norm((CCmdist(:)*length(I1)/(q-1))-((CCmdist(:)*length(I1)+CC(:))/q),2);
                                % ave_pre = (CCmdist/(q-1));
                                CCmdist=CCmdist+CC;% Now includes the current frame
                                % ave_cur = ((CCmdist)/q);
                                % ave_cur(ave_cur==0)=nan; %This makes sure you don't divide by zeros
                                %cnvg_est = 0;%nanmean(mean(mean(abs(ave_pre-ave_cur),1),2)./nanmean(nanmean(abs(ave_cur),1),2));
                                CC = []; %#ok% This clear is required for fine grids or big windows
                            end
                        else %if Corr(e)==4 %SPC processor
                           error('SPC Ensemble does not work with parallel processing. Try running again on a single core.')
                        end
                        corrtime=toc(t1);
                        if strcmpi(M,'EDeform') && (e~=1 || defloop~=1)
                            fprintf('deformation %4.0f of %4.0f...      %0.2i:%0.2i.%0.0f\n',q,length(I1dist),floor(deformtime/60),floor(rem(deformtime,60)),rem(deformtime,60)-floor(rem(deformtime,60)))                        
                        end
%                         fprintf('correlation %4.0f of %4.0f...      %0.2i:%0.2i.%0.0f Ensemble %%change %0.2e\n',q,length(I1dist),floor(corrtime/60),floor(rem(corrtime,60)),rem(corrtime,60)-floor(rem(corrtime,60)),cnvg_est)
                        fprintf('correlation %4.0f of %4.0f...      %0.2i:%0.2i.%0.0f\n',q,length(I1dist),floor(corrtime/60),floor(rem(corrtime,60)),rem(corrtime,60)-floor(rem(corrtime,60)))
                    end
                end
%                 if Corr(e)<4 %SCC or RPC processor
                CCm=zeros(size(CCmdist{1}));
                for i=1:length(CCmdist)
                    CCm=CCm+CCmdist{i}/length(I1);
                end
%                 elseif Corr(e)==2 %SPC processor
%                     CCm=zeros(size(CCmdist{1},1),size(CCmdist{1},2),size(CCmdist{1},3),length(I1));
%                     ind=1;
%                     for i=1:length(CCmdist)
%                         CCm(:,:,:,ind:ind+size(CCmdist{i},4)-1)=CCmdist{i};
%                         ind=ind+size(CCmdist{i},4);
%                     end
%                 end
            else
                
                for q=1:length(I1)

                    %load image pair and flip coordinates
                    im1=double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I1(q))]));
                    im2=double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I2(q))]));
                    if size(im1, 3) > 2
                        %Extract only red channel
                        if channel == 1;
                            im1 = im1(:,:,1);
                            im2 = im2(:,:,1);
                        %Extract only green channel
                        elseif channel == 2;
                            im1 = im1(:,:,2);
                            im2 = im2(:,:,2);
                        %Extract only blue channel
                        elseif channel == 3;
                            im1 = im1(:,:,3);
                            im2 = im2(:,:,3);
                        %Weighted average of channels (see rgb2gray for
                        %explanation of weighting factors)
                        elseif channel == 4;
                            im1 = 0.2989 * im1(:, :, 1) + 0.5870 * im1(:, :, 2) + 0.1140 * im1(:, :, 3);
                            im2 = 0.2989 * im2(:, :, 1) + 0.5870 * im2(:, :, 2) + 0.1140 * im2(:, :, 3);
                        %Evenly weighted mean of channels
                        elseif channel == 5;
                            im1 = (im1(:,:,1) + im1(:,:,2) + im1(:,:,3))/3;
                            im2 = (im2(:,:,1) + im2(:,:,2) + im2(:,:,3))/3;
                        %ensemble correlation of channels
                        elseif channel == 6;
                            im1=im1(:,:,1:3);
                            im2=im2(:,:,1:3);
                        end
                        else
                        %Take only red channel
                        im1 =im1(:,:,1);
                        im2 =im2(:,:,1);
                        channel = 1;
                    end

                        %  Flip images
                        %flipud only works on 2D matices.
%                     im1=flipud(im1(:,:,1));
%                     im2=flipud(im2(:,:,1));
                    im1 = im1(end:-1:1,:,:);
                    im2 = im2(end:-1:1,:,:);
%                     L=size(im1);

                    if strcmpi(M,'EDeform') && (e~=1 || defloop ~=1)
                        t1=tic;

                        %translate pixel locations
                        XD1 = XI+UI/2;
                        YD1 = YI+VI/2;
                        XD2 = XI-UI/2;
                        YD2 = YI-VI/2;

                        %preallocate deformed images
                        im1d = zeros(L);
                        im2d = zeros(L);
                        
                        %cardinal function interpolation
                        if Iminterp==1
                            for i=1:L(1)
                                for j=1:L(2)
                                    
                                    %image 1 interpolation
                                    nmin=max([1    (round(YD1(i,j))-3)]);
                                    nmax=min([L(1) (round(YD1(i,j))+3)]);
                                    mmin=max([1    (round(XD1(i,j))-3)]);
                                    mmax=min([L(2) (round(XD1(i,j))+3)]);
                                    for n=nmin:nmax
                                        for m=mmin:mmax
                                            wi = sin(pi*(m-XD1(i,j)))*sin(pi*(n-YD1(i,j)))/(pi^2*(m-XD1(i,j))*(n-YD1(i,j)));
                                            if channel ~= 6
                                                im1d(n,m)=im1d(n,m)+im1(i,j)*wi;
                                            else
                                                im1d(n,m,:)=im1d(n,m,:)+im1(i,j,:)*wi;
                                            end
                                        end
                                    end
                                    
                                    %image 2 interpolation
                                    nmin=max([1    (round(YD2(i,j))-3)]);
                                    nmax=min([L(1) (round(YD2(i,j))+3)]);
                                    mmin=max([1    (round(XD2(i,j))-3)]);
                                    mmax=min([L(2) (round(XD2(i,j))+3)]);
                                    for n=nmin:nmax
                                        for m=mmin:mmax
                                            wi = sin(pi*(m-XD2(i,j)))*sin(pi*(n-YD2(i,j)))/(pi^2*(m-XD2(i,j))*(n-YD2(i,j)));
                                            if channel ~= 6
                                                im2d(n,m)=im2d(n,m)+im2(i,j)*wi;
                                            else
                                                im2d(n,m,:)=im2d(n,m,:)+im2(i,j,:)*wi;
                                            end
                                        end
                                    end
                                    
                                end
                            end
                            
                            %cardinal function interpolation with Blackman filter
                        elseif Iminterp==2
                            
                            for i=1:L(1)
                                for j=1:L(2)
                                    
                                    %image 1 interpolation
                                    nmin=max([1    (round(YD1(i,j))-3)]);
                                    nmax=min([L(1) (round(YD1(i,j))+3)]);
                                    mmin=max([1    (round(XD1(i,j))-3)]);
                                    mmax=min([L(2) (round(XD1(i,j))+3)]);
                                    for n=nmin:nmax
                                        for m=mmin:mmax
                                            wi = sin(pi*(m-XD1(i,j)))*sin(pi*(n-YD1(i,j)))/(pi^2*(m-XD1(i,j))*(n-YD1(i,j)));
                                            bi = (0.42+0.5*cos(pi*(m-XD1(i,j))/3)+0.08*cos(2*pi*(m-XD1(i,j))/3))*(0.42+0.5*cos(pi*(n-YD1(i,j))/3)+0.08*cos(2*pi*(n-YD1(i,j))/3));
                                            if channel ~= 6
                                                im1d(n,m)=im1d(n,m)+im1(i,j)*wi*bi;
                                            else
                                                im1d(n,m,:)=im1d(n,m,:)+im1(i,j,:)*wi*bi;
                                            end
                                        end
                                    end
                                    
                                    %image 2 interpolation
                                    nmin=max([1    (round(YD2(i,j))-3)]);
                                    nmax=min([L(1) (round(YD2(i,j))+3)]);
                                    mmin=max([1    (round(XD2(i,j))-3)]);
                                    mmax=min([L(2) (round(XD2(i,j))+3)]);
                                    for n=nmin:nmax
                                        for m=mmin:mmax
                                            wi = sin(pi*(m-XD2(i,j)))*sin(pi*(n-YD2(i,j)))/(pi^2*(m-XD2(i,j))*(n-YD2(i,j)));
                                            bi = (0.42+0.5*cos(pi*(m-XD2(i,j))/3)+0.08*cos(2*pi*(m-XD2(i,j))/3))*(0.42+0.5*cos(pi*(n-YD2(i,j))/3)+0.08*cos(2*pi*(n-YD2(i,j))/3));
                                            if channel ~= 6
                                                im2d(n,m)=im2d(n,m)+im2(i,j)*wi*bi;
                                            else
                                                im2d(n,m,:)=im2d(n,m,:)+im2(i,j,:)*wi*bi;
                                            end
                                        end
                                    end
                                    
                                end
                            end

                        end

                        %clip lower values of deformed images
                        im1d(im1d<0)=0; im1d(isnan(im1d))=0;
                        im2d(im2d<0)=0; im2d(isnan(im2d))=0;
                        
                        deformtime=toc(t1);
                    end

                    t1=tic;
                    %correlate image pair and average correlations
%                   [Xc,Yc,CC]=PIVensemble(im1,im2,Corr(e),Wsize(e,:),Wres(e, :, :),0,D(e),Zeromean(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0));
                    if strcmpi(M,'EDeform') && (e~=1 || defloop ~=1)
                        [Xc,Yc,CC]=PIVensemble(im1d,im2d,Corr{e},Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),frac_filt(e),X(Eval>=0),Y(Eval>=0));
                    else
                        [Xc,Yc,CC]=PIVensemble(im1,im2,Corr{e},Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),frac_filt(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0));
                    end

                    if ~strcmpi(Corr{e},'SPC')   %SPC=4 %SCC or RPC 
                        if q==1
                            CCm=CC/length(I1);
                            %cnvg_est = 0;
                            CC = []; %#ok% This clear is required for fine grids or big windows
                        else
                            % cnvg_est = norm((CCm(:)*length(I1)/(q-1))-((CCm(:)*length(I1)+CC(:))/q),2);
                            % ave_pre = (CCm*length(I1)/(q-1));
                            CCm=CCm+CC/length(I1);% Now adding the current pass
                            % ave_cur = ((CCm*length(I1))/q);
                            % ave_cur(ave_cur==0)=nan; %This makes sure you don't divide by zero.
                            %cnvg_est = 0;%nanmean(mean(mean(abs(ave_pre-ave_cur),1),2)./nanmean(nanmean(abs(ave_cur),1),2));
                            CC = []; %#ok% This clear is required for fine grids or big windows
                        end
                    else %if Corr(e)==4 %SPC processor, should this be just ELSE?
                        if q==1
                            CCm=CC;
                        else
                            CCm.U=[CCm.U,CC.U];
                            CCm.V=[CCm.V,CC.V];
                            CCm.C=[CCm.C,CC.C];
                        end
                        %cnvg_est = 0;
                    end
                    corrtime=toc(t1);
                    if strcmpi(M,'EDeform') && (e~=1 || defloop~=1)
                        fprintf('deformation %4.0f of %4.0f...      %0.2i:%0.2i.%0.0f\n',q,length(I1),floor(deformtime/60),floor(rem(deformtime,60)),rem(deformtime,60)-floor(rem(deformtime,60)))
                    end
%                     fprintf('correlation %4.0f of %4.0f...      %0.2i:%0.2i.%0.0f Ensemble %%change %0.2e\n',q,length(I1),floor(corrtime/60),floor(rem(corrtime,60)),rem(corrtime,60)-floor(rem(corrtime,60)),cnvg_est)
                    fprintf('correlation %4.0f of %4.0f...      %0.2i:%0.2i.%0.0f\n',q,length(I1),floor(corrtime/60),floor(rem(corrtime,60)),rem(corrtime,60)-floor(rem(corrtime,60)))
                end
            end

            Z=[size(CCm,2), size(CCm,1),length(X(Eval>=0))];
            ZZ=ones(Z(1),Z(2));

            if Peakswitch(e) || (Valswitch(e) && extrapeaks(e))
                Uc=zeros(Z(3),3);
                Vc=zeros(Z(3),3);
                Cc=zeros(Z(3),3);
                Dc=zeros(Z(3),3);
                Ub=repmat(Ub,[1 3]);
                Vb=repmat(Vb,[1 3]);
                Eval=repmat(Eval,[1 3]);
            else
                Uc=zeros(Z(3),1);Vc=zeros(Z(3),1);Cc=[];Dc=[];
            end

            if ~strcmpi(Corr{e},'SPC')
                t1=tic;
                for s=1:Z(3) %Loop through grid points    
                    %Find the subpixel fit of the average correlation matrix
                    [Uc(s,:),Vc(s,:),Cc(s,:),Dc(s,:)]=subpixel(CCm(:,:,s),Z(2),Z(1),ZZ,Peaklocator(e),Peakswitch(e) || (Valswitch(e) && extrapeaks(e)),D(e,:));
                end
                peaktime=toc(t1);
                fprintf('peak fitting...                  %0.2i:%0.2i.%0.0f\n',floor(peaktime/60),floor(rem(peaktime,60)),rem(peaktime,60)-floor(rem(peaktime,60)))
            elseif strcmpi(Corr{e},'SPC') %SPC processor
                %RPC filter for weighting function
                wt = energyfilt(Z(2),Z(1),D(e,:),0);
                wtX=wt(Z(1)/2+1,:)';
                cutoff=2/pi/D(e,2);
                wtX(wtX<cutoff)=0;
                wtY=wt(:,Z(2)/2+1);
                cutoff=2/pi/D(e,1);
                wtY(wtY<cutoff)=0;
                lsqX=(0:Z(2)-1)-Z(2)/2;
                lsqY=(0:Z(1)-1)-Z(1)/2;
                lsqX=repmat(lsqX,[1 length(I1)]);
                lsqY=repmat(lsqY,[1 length(I1)]);               
                Qp=squeeze(CCm.C(1,:,:)./CCm.C(2,:,:));
                Qp_norm=(Qp-repmat(min(Qp),[length(I1) 1]))./repmat(max(Qp)-min(Qp),[length(I1) 1]);

                for s=1:Z(3) 
                    wtX_cum=reshape(repmat(wtX,[1 length(I1)]),[1 numel(wtX)*length(I1)]);
                    wtY_cum=reshape(repmat(wtY,[1 length(I1)]),[1 numel(wtY)*length(I1)]);

                    for q=1:length(I1)
                        indX=(1:Z(2))+Z(2)*(q-1);
                        indY=(1:Z(1))+Z(1)*(q-1);
                        wtX_cum(indX)=wtX_cum(indX).*Qp_norm(q,s);
                        wtY_cum(indY)=wtX_cum(indY).*Qp_norm(q,s);
                    end

                    %Perform the weighted lsq regression
                    Uc(s)= wlsq(CCm.U(1,:,s),lsqX,wtX_cum)*Z(2)/2/pi;
                    Vc(s)=-wlsq(CCm.V(1,:,s),lsqY,wtY_cum)*Z(1)/2/pi;
                    Cc(s)=max(max(CCm.C(:,:,s)));
                    Dc(s)=0;
                end
            end

            if strcmpi(M,'EDeform') && (e~=1 || defloop ~=1)
                U(Eval>=0)=Uc(:)+Ub(Eval>=0);
                V(Eval>=0)=Vc(:)+Vb(Eval>=0);
            else
                U(Eval>=0)=Uc(:)+round(Ub(Eval>=0));
                V(Eval>=0)=Vc(:)+round(Vb(Eval>=0));
            end
            if Peakswitch(e) || (Valswitch(e) && extrapeaks(e))%~isempty(Cc)
                C(Eval>=0)=Cc(:);
                Di(Eval>=0)=Dc(:);
            end

            %validation
            if Valswitch(e)
                %keyboard
                t1=tic;

                [Uval,Vval,Evalval,Cval,Dval]=VAL(X,Y,U,V,Eval,C,Di,Threshswitch(e),UODswitch(e),Bootswitch(e),extrapeaks(e),...
                    Uthresh(e,:),Vthresh(e,:),UODwinsize(e,:,:),UODthresh(e,UODthresh(e,:)~=0)',Bootper(e),Bootiter(e),Bootkmax(e));

                valtime=toc(t1);
                fprintf('validation...                    %0.2i:%0.2i.%0.0f\n',floor(valtime/60),floor(rem(valtime,60)),rem(valtime,60)-floor(rem(valtime,60)))

            else
                Uval=U(:,1);Vval=V(:,1);Evalval=Eval(:,1);
                if ~isempty(C)
                    Cval=C(:,1);
                    Dval=Di(:,1);
                else
                    Cval=[];
                    Dval=[];
                end
            end

            % --- Iterative Deformation Check ---
            if strcmpi(M,'EDeform')
                if defloop == 1
                    Ud = Uval; Vd = Vval;
                else
                    defconvU(e,defloop) = norm(Uval - Ud,2);
                    defconvV(e,defloop) = norm(Vval - Vd,2);
                    Ud = Uval; Vd = Vval;
                end
                if defloop == maxdefloop(e) || (defloop ~= 1 && defloop >= mindefloop(e) && defconvU(e,defloop) <= condefloop(e) && defconvV(e,defloop) <= condefloop(e))
                    if maxdefloop(e) ~= 1
                        wbase{e,:} = sprintf([wbase_org{e,:} 'deform' num2str(defloop) '_']);
                    end
                    defloop = 1;
                else
                    defloop = defloop+1;
                end
            end

            %write output
            if Writeswitch(e) && defloop == 1
                t1=tic;

                if Peakswitch(e)
                    if PeakVel(e) && ~strcmpi(Corr{e},'SPC')
                        U=[Uval,U(:,1:PeakNum(e))];
                        V=[Vval,V(:,1:PeakNum(e))];
                        Eval=[Evalval,Eval(:,1:PeakNum(e))];
                    else
                        U=Uval; V=Vval; Eval=Evalval;
                    end
                    if PeakMag(e)
                        C=[Cval,C(:,1:PeakNum(e))];
                        Di=[Dval,Di(:,1:PeakNum(e))];
                    else
                        C=Cval;
                        Di=Dval;
                    end
                else
                    U=Uval; V=Vval; Eval=Evalval; C=Cval; Di=Dval;
                end

                %convert to physical units
                Xval=X;Yval=Y;
                X=X*Mag;Y=Y*Mag;
                U=U*Mag/dt;V=V*Mag/dt;

                %convert to matrix if necessary
                if size(X,2)==1
                    [X,Y,U,V,Eval,C,Di]=matrixform(X,Y,U,V,Eval,C,Di);
                end

                %remove nans from data, replace with zeros
                U(Eval<0 | isinf(U))=0;V(Eval<0 | isinf(V))=0;

                if str2double(Data.datout)
                    time=I1(1)/Freq;
                    %write_dat_val_C([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.dat' ],I1(1))],X,Y,U,V,Eval,C,e,0,frametitle);
                    write_dat_val_C([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.dat' ],I1(1))],X,Y,U,V,Eval,C,Di,e,time,char(wbase(e,:)));
                end
                if str2double(Data.multiplematout)
                    save([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.mat' ],I1(1))],'X','Y','U','V','Eval','C','Di')
                end
                if saveplane(e) && ~strcmpi(Corr{e},'SPC')
                    Xloc = Xc;Yloc=Yc;%#ok
                    save(sprintf(['%s%scorrplanes_%0.' Data.imzeros 'i.mat' ],pltdirec,wbase{e,:},I1(1)),'Xloc','Yloc','CCm')
                    clear Xloc Yloc
                end
                X=Xval;Y=Yval;

                savetime=toc(t1);
                fprintf('save time...                     %0.2i:%0.2i.%0.0f\n',floor(savetime/60),floor(rem(savetime,60)),rem(savetime,60)-floor(rem(savetime,60)))
            end
            U=Uval; V=Vval;
        
            if e~=P || defloop ~= 1 %Not the last pass or not finished converging the final pass
                t1=tic;
                
                %reshape from list of grid points to matrix
                X=reshape(X,[S(1),S(2)]);
                Y=reshape(Y,[S(1),S(2)]);
                U=reshape(U(:,1),[S(1),S(2)]);
                V=reshape(V(:,1),[S(1),S(2)]);

                %velocity smoothing
                if Velsmoothswitch(e)==1
                    [U,V]=VELfilt(U,V,UODwinsize(e,:,:),Velsmoothfilt(e));
                end

                %velocity interpolation
                UI = VFinterp(X,Y,U,XI,YI,Velinterp);
                VI = VFinterp(X,Y,V,XI,YI,Velinterp);

                interptime=toc(t1);
                fprintf('velocity interpolation...        %0.2i:%0.2i.%0.0f\n',floor(interptime/60),floor(rem(interptime,60)),rem(interptime,60)-floor(rem(interptime,60)))
            end
            
            if defloop == 1
                eltime=toc(tf);
                %output text
                fprintf('total pass time...               %0.2i:%0.2i.%0.0f\n',floor(eltime/60),floor(rem(eltime,60)),rem(eltime,60)-floor(rem(eltime,60)))
                frametime(e)=eltime;
                comptime=mean(frametime(1:e))*(P-e);
                fprintf('estimated job completion time... %0.2i:%0.2i:%0.2i\n',floor(comptime/3600),floor(rem(comptime,3600)/60),floor(rem(comptime,60)))
            end

        end
        
    case 'Multiframe'
        %% --- Multiframe ---
        I1_full=str2double(Data.imfstart):str2double(Data.imfstep):str2double(Data.imfend);
        time_full=str2double(Data.imfstart):(str2double(Data.imfend)+str2double(Data.imcstep));

        corrtime=zeros(P,1);
        valtime=zeros(P,1);
        savetime=zeros(P,1);
        interptime=zeros(P,1);

        %single-pulsed
        if round(1/Freq*10^6)==round(dt)
            time_full(2,:)=time_full(1,:);
        else
            %double-pulsed
            sample_t=1/Freq*10^6;
            for n=3:2:length(time_full)
                time_full(2,n)=floor(n/2)*sample_t/dt;
                time_full(2,n-1)=(floor((n-2)/2)*sample_t+dt)/dt;
            end
            time_full(2,end)=time_full(2,end-1)+1;
        end

        if I1(1)==I1_full(1)
            qstart=1;
        else
            qstart=Nmax+1;
        end
        if I1(end)==I1_full(end)
            qend=length(I1);
        else
            qend=length(I1)-Nmax;
        end
        frametime=nan(length(qstart:qend),1);
        
        for q=qstart:qend
            tf=tic;
            frametitle=['Frame' sprintf(['%0.' Data.imzeros 'i'],I1(q)) ' and Frame' sprintf(['%0.' Data.imzeros 'i'],I2(q))];
            
            %load dynamic mask and flip coordinates
            if strcmp(Data.masktype,'dynamic')
                mask = double(imread([maskbase sprintf(['%0.' Data.maskzeros 'i.' Data.maskext],maskname(q))]));
                mask = flipud(mask);
            end
            
            %load image pairs, compute delta-t, and flip coordinates
            if q-Nmax<1 && q+Nmax>length(I1)
                N=min([q,length(I1)-q+1]);
            elseif q-Nmax<1
                N=q;
            elseif q+Nmax>length(I1)
                N=length(I1)-q+1;
            else
                N=Nmax+1;
            end
            im1=zeros(size(mask,1),size(mask,2),N); im2=im1;Dt=zeros(N,1);
            for n=1:N
                im1_temp=double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I1(q)-(n-1))]));
                im2_temp=double(imread([imbase sprintf(['%0.' Data.imzeros 'i.' Data.imext],I2(q)+(n-1))]));
                im1(:,:,n)=flipud(im1_temp(:,:,1));
                im2(:,:,n)=flipud(im2_temp(:,:,1));
                if Zeromean(e)==1
                    im1(:,:,n)=im1(:,:,n)-mean(mean(im1(:,:,n)));
                    im2(:,:,n)=im2(:,:,n)-mean(mean(im2(:,:,n)));
                end
                
                imind1= time_full(1,:)==I1(q)-(n-1);
                imind2= time_full(1,:)==I2(q)+(n-1);
                Dt(n)=time_full(2,imind2)-time_full(2,imind1);
            end
            L=size(im1);

            %initialize grid and evaluation matrix
            [XI,YI]=IMgrid(L,[0 0]);

            UI = zeros(size(XI));
            VI = zeros(size(YI));

            for e=1:P
                t1=tic;
                [X,Y]=IMgrid(L,Gres(e,:),Gbuf(e,:));
                S=size(X);X=X(:);Y=Y(:);

                if ~strcmpi(Corr{e},'SPC')
                    U=zeros(size(X,1),3,N);
                    V=zeros(size(X,1),3,N);
                    C=zeros(size(X,1),3,N);
                    Di=zeros(size(X,1),3,N);
                    Cp=zeros(Wsize(e,1),Wsize(e,2),size(X,1),N);
                    Uval=zeros(size(X,1),3);
                    Vval=zeros(size(X,1),3);
                    Cval=zeros(size(X,1),3);
                    Dval=zeros(size(X,1),3);
                    Eval=repmat(reshape(downsample(downsample( mask(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1),[1 3]);
                    Eval(Eval==0)=-1;
                    Eval(Eval>0)=0;
                    Uc=zeros(sum(Eval(:,1)>=0),3,N);
                    Vc=zeros(sum(Eval(:,1)>=0),3,N);
                    Cc=zeros(sum(Eval(:,1)>=0),3,N);
                    Dc=zeros(sum(Eval(:,1)>=0),3,N);
                    
                    for t=1:N
                        Ub = reshape(downsample(downsample( UI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1).*Dt(t);
                        Vb = reshape(downsample(downsample( VI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1).*Dt(t);

                        %correlate image pair
%                         [Xc,Yc,Uc(:,:,t),Vc(:,:,t),Cc(:,:,t)]=PIVwindowed(im1(:,:,t),im2(:,:,t),Corr(e),Wsize(e,:),Wres(e, :, :),0,D(e),Zeromean(e),Peaklocator(e),1,X(Eval(:,1)>=0),Y(Eval(:,1)>=0),Ub(Eval(:,1)>=0),Vb(Eval(:,1)>=0));
                        [Xc,Yc,Uc(:,:,t),Vc(:,:,t),Cc(:,:,t),Dc(:,:,t),Cp(:,:,:,t)]=PIVwindowed(im1(:,:,t),im2(:,:,t),Corr{e},Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),Peaklocator(e),1,frac_filt(e),saveplane(e),X(Eval(:,1)>=0),Y(Eval(:,1)>=0),Ub(Eval(:,1)>=0),Vb(Eval(:,1)>=0));
                    end
                    U(repmat(Eval>=0,[1 1 N]))=Uc;
                    V(repmat(Eval>=0,[1 1 N]))=Vc;
                    C(repmat(Eval>=0,[1 1 N]))=Cc;
                    Di(repmat(Eval>=0,[1 1 N]))=Dc;

                    velmag=sqrt(U(:,1,:).^2+V(:,1,:).^2);
                    Qp=C(:,1,:)./C(:,2,:).*(1-ds./velmag);
%                     Qp=1-2.*exp(-0.5)./velmag.*(C(:,1,:)./C(:,2,:)-1).^(-1);
                    [Qmax,t_opt]=max(Qp,[],3);%#ok
                    for i=1:size(U,1)
                        Uval(i,:)=U(i,:,t_opt(i));
                        Vval(i,:)=V(i,:,t_opt(i));
                        Cval(i,:)=C(i,:,t_opt(i));
                        Dval(i,:)=Di(i,:,t_opt(i));
                    end

                    try
                        U=Uval./repmat(Dt(t_opt)',[1 3]);
                        V=Vval./repmat(Dt(t_opt)',[1 3]);
                    catch
                        U=Uval./repmat(Dt(t_opt),[1 3]);
                        V=Vval./repmat(Dt(t_opt),[1 3]);
                    end
                    
                else
                    U=zeros(length(X),1);
                    V=zeros(length(X),1);
                    Eval=reshape(downsample(downsample( mask(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
                    Eval(Eval==0)=-1;
                    Eval(Eval>0)=0;
                    
                    Ub = reshape(downsample(downsample( UI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
                    Vb = reshape(downsample(downsample( VI(Y(1):Y(end),X(1):X(end)),Gres(e,2))',Gres(e,1))',length(X),1);
%                     [Xc,Yc,Uc,Vc,Cc,t_optc]=PIVphasecorr(im1,im2,Wsize(e,:), Wres(e, :, :),0,D(e),Zeromean(e),Peakswitch(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0),Dt);
                    [Xc,Yc,Uc,Vc,Cc,t_optc]=PIVphasecorr(im1,im2,Wsize(e,:),Wres(:, :, e),0,D(e,:),Zeromean(e),Peakswitch(e),X(Eval>=0),Y(Eval>=0),Ub(Eval>=0),Vb(Eval>=0),Dt);
                    if Peakswitch(e)
                        C=zeros(length(X),3);
                        Di=zeros(length(X),3);
                        C(repmat(Eval,[1 3])>=0)=Cc;
                        t_opt=zeros(size(X));
                        t_opt(Eval>=0)=t_optc;
                    else
                        C=[];t_opt=[];Di=[];
                    end
                    U(Eval>=0)=Uc;V(Eval>=0)=Vc;
                end
                
                corrtime(e)=toc(t1);
                
                %validation
                if Valswitch(e)
                    t1=tic;
                    
                    [Uval,Vval,Evalval,Cval,Dval]=VAL(X,Y,U,V,Eval,C,Di,Threshswitch(e),UODswitch(e),Bootswitch(e),extrapeaks(e),...
                        Uthresh(e,:),Vthresh(e,:),UODwinsize(e,:,:),UODthresh(e,UODthresh(e,:)~=0)',Bootper(e),Bootiter(e),Bootkmax(e));
                    
                    valtime(e)=toc(t1);
                else
                    Uval=U(:,1);Vval=V(:,1);Evalval=Eval(:,1);
                    if ~isempty(C)
                        Cval=C(:,1);
                        Dval=Di(:,1);
                    else
                        Cval=[];
                        Dval=[];
                    end
                end

                %write output
                if Writeswitch(e) 
                    t1=tic;
                    if Peakswitch(e)                    
                        if PeakVel(e) && ~strcmpi(Corr{e},'SPC')
                            U=[Uval(:,1),U(:,1:PeakNum(e))];
                            V=[Vval(:,1),V(:,1:PeakNum(e))];
                            Eval=[Evalval(:,1),Eval(:,1:PeakNum(e))];
                        else
                            U=Uval(:,1); V=Vval(:,1);Eval=Evalval(:,1);
                        end
                        if PeakMag(e)
                            C=[Cval(:,1),C(:,1:PeakNum(e))];
                            Di=[Dval(:,1),Di(:,1:PeakNum(e))];                            
                        else
                            C=[];
                            Di=[];
                        end
                    else
                        t_opt=[];
                    end
                    %convert to physical units
                    Xval=X;Yval=Y;
                    X=X*Mag;Y=Y*Mag;
                    U=U*Mag./dt;V=V*Mag./dt;

                    %convert to matrix if necessary
                    if size(X,2)==1
                        [X,Y,U,V,Eval,C,Di]=matrixform(X,Y,U,V,Eval,C,Di);
                        if Peakswitch(e)
                            t_opt=reshape(t_opt,size(X,1),size(X,2));
                        end
                    end

                    %remove nans from data, replace with zeros
                    U(Eval<0|isinf(U))=0;V(Eval<0|isinf(V))=0;

                    if str2double(Data.datout)
%                         q_full=find(I1_full==I1(q),1,'first');
%                         time=(q_full-1)/Freq;
                        time=I1(q)/Freq;
                        %write_dat_val_C([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.dat' ],I1(q))],X,Y,U,V,Eval,C,e,time,frametitle,t_opt);
                        write_dat_val_C([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.dat' ],I1(q))],X,Y,U,V,Eval,C,Di,e,time,char(wbase(e,:)),t_opt);
                    end
                    if str2double(Data.multiplematout)
                        save([pltdirec char(wbase(e,:)) sprintf(['%0.' Data.imzeros 'i.mat' ],I1(q))],'X','Y','U','V','Eval','C','Di','t_opt')
                    end
                    if saveplane(e) && ~strcmpi(Corr{e},'SPC')
                        Xloc = Xc;Yloc=Yc;C_planes=Cp;%#ok
                        save(sprintf(['%s%scorrplanes_%0.' Data.imzeros 'i.mat' ],pltdirec,wbase{e,:},I1(q)),'Xloc','Yloc','C_planes')
                        clear Xloc Yloc C_planes
                    end
                    X=Xval;Y=Yval;
                    
                    savetime(e)=toc(t1);
                end
                U=Uval; V=Vval;
                
                if e~=P
                    %reshape from list of grid points to matrix
                    X=reshape(X,[S(1),S(2)]);
                    Y=reshape(Y,[S(1),S(2)]);
                    U=reshape(U(:,1),[S(1),S(2)]);
                    V=reshape(V(:,1),[S(1),S(2)]);

                    t1=tic;

                    %velocity smoothing
                    if Velsmoothswitch(e)==1
                        [U,V]=VELfilt(U,V,UODwinsize(e,:,:),Velsmoothfilt(e));
                    end
                    
                    %velocity interpolation
                    UI = VFinterp(X,Y,U,XI,YI,Velinterp);
                    VI = VFinterp(X,Y,V,XI,YI,Velinterp);

                    interptime(e)=toc(t1);
                end
                Uval=[];Vval=[];Cval=[];
            end

            eltime=toc(tf);
            %output text
            fprintf('\n----------------------------------------------------\n')
            fprintf(['Job: ',Data.batchname,'\n'])
            fprintf([frametitle ' Completed (' num2str(q+1-qstart) '/' num2str(length(qstart:qend)) ') at %s \n'], datestr(now));
%             fprintf(1, 'Frame completed at %s \n', datestr(now)); % Print the date and time at which frame was completed
            fprintf('----------------------------------------------------\n')
            for e=1:P
                fprintf('correlation...                   %0.2i:%0.2i.%0.0f\n',floor(corrtime(e)/60),floor(rem(corrtime(e),60)),rem(corrtime(e),60)-floor(rem(corrtime(e),60)))
                if Valswitch(e)
                    fprintf('validation...                    %0.2i:%0.2i.%0.0f\n',floor(valtime(e)/60),floor(rem(valtime(e),60)),rem(valtime(e),60)-floor(rem(valtime(e),60)))
                end
                if Writeswitch(e)
                    fprintf('save time...                     %0.2i:%0.2i.%0.0f\n',floor(savetime(e)/60),floor(rem(savetime(e),60)),rem(savetime(e),60)-floor(rem(savetime(e),60)))
                end
                if e~=P
                    fprintf('velocity interpolation...        %0.2i:%0.2i.%0.0f\n',floor(interptime(e)/60),floor(rem(interptime(e),60)),rem(interptime(e),60)-floor(rem(interptime(e),60)))
                end
            end
            fprintf('total frame time...              %0.2i:%0.2i.%0.0f\n',floor(eltime/60),floor(rem(eltime,60)),rem(eltime,60)-floor(rem(eltime,60)))
            frametime(q+1-qstart)=eltime;
            comptime=nanmean(frametime(1:q+1-qstart))*(length(qstart:qend)-(q+1-qstart));
            fprintf('estimated job completion time... %0.2i:%0.2i:%0.2i\n\n',floor(comptime/3600),floor(rem(comptime,3600)/60),floor(rem(comptime,60)))
        end
end

%signal job complete
beep,pause(0.2),beep

end


