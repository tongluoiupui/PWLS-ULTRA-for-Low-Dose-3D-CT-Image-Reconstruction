%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Xuehang Zheng, UM-SJTU Joint Institute
clear ; close all;
addpath(genpath('../data/2Dxcat'));
addpath(genpath('../toolbox'));
%% setup target geometry and weight
down = 1; % downsample rate
sg = sino_geom('ge1', 'units', 'mm', 'strip_width', 'd', 'down', down);
ig = image_geom('nx', 420, 'dx', 500/512, 'down', down);
ig.mask = ig.circ > 0;
% A = Gtomo2_dscmex(sg, ig,'nthread', maxNumCompThreads*2);
A = Gtomo2_dscmex(sg, ig,'nthread', jf('ncore')*2-1);
% if neccessary, one could modify maxNumComThreads/jf('ncore') to make full
% use of threads of your machine to accelerate the computation of 
% forward and back projections.

%% load external parameter
I0 = 1e4; % photon intensity

% load PWLS-EP Recon as initialization: xrlalm
load('xrlalm1e4_l2b16_os24_iter50.mat'); % change intial EP image when I0 is changed!
% load('xrlalm5e3_l2b16dot5_os24_iter50.mat');

%load learned dictionary: mOmega
load('../data/2Dxcat/LearntDict/T20_err1e-1_iter1000.mat');
mOmega = info.mOmega;

%load ground truth image: xtrue
load('slice420.mat');

dir = ['../data/2Dxcat/tmp/' num2str(I0)];
printm('Loading external sinogram, weight, fbp...');
load([dir '/sino_fan.mat']);
load([dir '/wi.mat']);
load([dir '/xfbp.mat']);
% load([dir '/kappa.mat']);
% figure name 'xfbp'
% imshow(xfbp, [800 1200]);

%% setup edge-preserving regularizer
ImgSiz =  [ig.nx ig.ny];  % image size
PatSiz =  [8 8];          % patch size
SldDist = [1 1];          % sliding distance

nblock = 4;            % Subset Number
nIter = 2;             % I--Inner Iteration
nOuterIter = 1000;     % T--Outer Iteration
pixmax = inf;         % Set upper bond for pixel values

printm('Pre-calculating denominator D_A...');
% denom = abs(A)' * col(reshape(sum(abs(A)'), size(wi)) .* wi);
% denom= abs(A)'*(wi(:).*(abs(A)*ones(size(xrla_msk,1),1)));
load([dir '/denom.mat']);

Ab = Gblock(A, nblock); clear A

% pre-compute D_R
PP = im2colstep(ones(ImgSiz,'single'), PatSiz, SldDist);
KK = col2imstep(single(PP), ImgSiz, PatSiz, SldDist);

for beta =  [7e4]
    for T =  [25]        % maximal number of atoms
        for EPSILON = 55 % sparsification error
            
            fprintf('beta = %.1e, T = %g, EPSILON = %g: \n', beta, T, EPSILON);
            
            D_R = 2 * beta * KK(ig.mask);
            % construct regularizer R(x)
            R = Reg_DL(ig.mask, PatSiz, ImgSiz, SldDist, beta, T, EPSILON, mOmega);
            
            info = struct('intensity',I0,'SldDist',SldDist,'beta',beta,'T',T,'EPSILON',EPSILON,...
                'nblock',nblock,'nIter',nIter,'pixmax',pixmax,'transform',mOmega,...
                'xrla',[],'RMSE',[],'SSIM',[],'relE',[],'perc',[],'cost',[]);
            
            xini = xrlalm .* ig.mask;    %initial EP image
            xrla_msk = xrlalm(ig.mask);
%             xini = xfbp .* ig.mask;     %initial FBP image
%             xrla_msk = xfbp(ig.mask);
            info.xrla = xini;
    
            %% Recon
            SqrtPixNum = sqrt(sum(ig.mask(:)>0)); % sqrt(pixel numbers in the mask)
            stop_diff_tol = 1e-3; % HU
            
            % profile on
            for ii=1:nOuterIter
                xold = xrla_msk;
                AAA(1,ii) = norm(xrla_msk - xtrue(ig.mask)) / SqrtPixNum;
                fprintf('RMSE = %g, ', AAA(1,ii));
                info.RMSE = AAA(1,:);
                AAA(2,ii)= ssim(info.xrla, xtrue);
                fprintf('SSIM = %g\n', AAA(2,ii));
                info.SSIM = AAA(2,:);
                
                fprintf('Iteration = %d:\n', ii);
                [xrla_msk, cost] = pwls_os_rlalm(xrla_msk, Ab, reshaper(sino,'2d'), reshaper(wi,'2d'),  ...
                    R, denom, D_R, 'pixmax', pixmax, 'chat', 0, 'alpha', 1.999, 'rho', [], 'niter', nIter);
                
                info.perc(:,ii) = R.nextOuterIter();
                fprintf('perc = %g, ', info.perc(:,ii));
                
                %     info.cost(:,ii) = cost;
                info.relE(:,ii) =  norm(xrla_msk - xold) / SqrtPixNum;
                fprintf('relE = %g\n', info.relE(:,ii));
                if info.relE(:,ii) < stop_diff_tol
                    break
                end
                info.xrla = ig.embed(xrla_msk);
                figure(120), imshow(info.xrla, [800 1200]); drawnow;
                
            end
            %%
%             save(sprintf('./result/%.1e_beta%.1e_T%g_Err%g.mat', I0, beta, T, EPSILON), 'info')
            % imshow(cat(2, info.xrla, xini), [800 1200]);
            
        end
    end
end


% figure name 'SSIM'
% plot(info.SSIM);
% xlabel('Number of Total Iteration','fontsize',18)
% ylabel('SSIM','fontsize',18)
% legend('PWLS-ST')

figure name 'RMSE'
plot(info.RMSE,'-+')
xlabel('Number of Outer Iteration','fontsize',18)
ylabel('RMSE(HU)','fontsize',18)
legend('PWLS-DL')

% figure name 'compare'
% imshow(cat(2, info.xrla, xini), [800 1200]);colorbar;

% save('info.mat', 'info')
% export_fig x.pdf -transparent
