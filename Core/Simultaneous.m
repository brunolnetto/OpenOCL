classdef Simultaneous < handle
  %SIMULTANEOUS Direct collocation discretization of OCP to NLP
  %   Discretizes continuous OCP formulation to be solved as an NLP
  
  methods (Static)
    
    function varsStruct = vars(phaseList)
      
      varsStruct = OclStructure();
      phaseStruct = [];
      
      for k=1:length(phaseList)
        phase = phaseList{k};
        phaseStruct = OclStructure();
        phaseStruct.addRepeated({'states','integrator','controls','parameters','h'}, ...
                            {phase.states, ...
                             phase.integrator.vars, ...
                             phase.controls, ...
                             phase.parameters, ...
                             OclMatrix([1,1])}, length(phase.H_norm));
        phaseStruct.add('states', phase.states);

        varsStruct.add('phases', phaseStruct);
      end
      if length(phaseList) == 1
        varsStruct = phaseStruct;
      end
    end
    
    function timesStruct = times(nit, N)
      timesStruct = OclStructure();
      timesStruct.addRepeated({'states', 'integrator', 'controls'}, ...
                                   {OclMatrix([1,1]), OclMatrix([nit,1]), OclMatrix([1,1])}, N);
      timesStruct.add('states', OclMatrix([1,1]));
    end
    
    
    function ig = ig(self)
      ig = self.getInitialGuess();
    end
    
    function guess = igFromBounds(~, bounds)
      % Averages the bounds to get an initial guess value.
      % Makes sure no nan values are produced, defaults to 0.
      guess = (bounds.lower + bounds.upper)/2;
      if isnan(guess) && ~isinf(bounds.lower)
        guess = bounds.lower;
      elseif isnan(guess) && ~isinf(bounds.upper)
        guess = bounds.upper;
      else
        guess = 0;
      end
    end
    
    function ig = getInitialGuess(varsStruct, phaseList)
      % creates an initial guess from the information that we have about
      % bounds, phases etc.
      
      ig = Variable.create(varsStruct,0);
      
      for k=1:length(phaseList)
        
        phase = phaseList{k};
        igPhase = ig.get('phases', k);
        
        names = fieldnames(phase.bounds);
        for l=1:length(names)
          id = names{l};
          igPhase.get(id).set(Simultaneous.igFromBounds(phase.bounds.(id)));
        end
        
        names = fieldnames(phase.bounds0);
        for l=1:length(names)
          id = names{l};
          igPhase.get(id).set(Simultaneous.igFromBounds(phase.bounds0.(id)));
        end
        
        names = fieldnames(phase.boundsF);
        for l=1:length(names)
          id = names{l};
          igPhase.get(id).set(Simultaneous.igFromBounds(phase.boundsF.(id)));
        end

        % linearily interpolate guess
        phaseStruct = varsStruct.get('phases',k).flat();
        phaseFlat = Variable.create(phaseStruct.flat(), igPhase.value);
        
        names = igPhase.children();
        for i=1:length(names)
          id = names{i};
          igId = phaseFlat.get(id);
          igStart = igId(:,:,1).value;
          igEnd = igId(:,:,end).value;
          s = igId.size();
          gridpoints = reshape(linspace(0, 1, s(3)), 1, 1, s(3));
          gridpoints = repmat(gridpoints, s(1), s(2));
          interpolated = igStart + gridpoints.*(igEnd-igStart);
          phaseFlat.get(id).set(interpolated);
        end
        igPhase.set(phaseFlat.value);
        
        names = fieldnames(phase.parameterBounds);
        for i=1:length(names)
          id = names{i};
          igPhase.get(id).set(Simultaneous.igFromBounds(phase.parameterBounds.(id)));
        end
        
        % ig for timesteps
        if isempty(phase.T)
          H = phase.H_norm;
        else
          H = phase.H_norm.*phase.T;
        end
        igPhase.get('h').set(H);
      
      end
    end
    
    function [lowerBounds,upperBounds] = getNlpBounds(phaseList)
      
      lowerBounds = cell(length(phaseList), 1);
      upperBounds = cell(length(phaseList), 1);
      
      for k=1:length(phaseList)
        
        phase = phaseList{k};
        [nv_phase,~] = Simultaneous.nvars(H_norm, nx, ni, nu, np);
        
        lb_phase = -inf * ones(nv_phase,1);
        ub_phase = inf * ones(nv_phase,1);

        % number of variables in one control interval
        % + 1 for the timestep
        nci = nx+ni+nu+np+1;

        % Finds indizes of the variables in the NlpVars array.
        % cellfun is similar to python list comprehension 
        % e.g. [range(start_i,start_i+nx) for start_i in range(1,nv,nci)]
        X_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+nx-1)', 1:nci:nv_phase, 'UniformOutput', false));
        I_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+ni-1)', nx+1:nci:nv_phase, 'UniformOutput', false));
        U_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+nu-1)', nx+ni+1:nci:nv_phase, 'UniformOutput', false));
        P_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+np-1)', nx+ni+nu+1:nci:nv_phase, 'UniformOutput', false));
        H_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i)', nx+ni+nu+np+1:nci:nv_phase, 'UniformOutput', false));
        
        % states
        for m=size(X_indizes,2)
          lb_phase(X_indizes(:,m)) = phase.stateBounds.lower;
          ub_phase(X_indizes(:,m)) = phase.stateBounds.upper;
        end
        
        lb_phase(X_indizes(:,1)) = phase.stateBounds0.lower;
        ub_phase(X_indizes(:,1)) = phase.stateBounds0.upper;
        
        lb_phase(X_indizes(:,end)) = phase.stateBoundsF.lower;
        ub_phase(X_indizes(:,end)) = phase.stateBoundsF.upper;
        
        % integrator bounds
        for m=size(I_indizes,2)
          lb_phase(I_indizes(:,m)) = phase.integrator.stateBounds.lower;
          ub_phase(I_indizes(:,m)) = phase.integrator.stateBounds.lower;
        end
        
        for m=size(I_indizes,2)
          lb_phase(I_indizes(:,m)) = phase.integrator.algvarBounds.lower;
          ub_phase(I_indizes(:,m)) = phase.integrator.algvarBounds.lower;
        end
        
        % controls
        for m=size(U_indizes,2)
          lb_phase(U_indizes(:,m)) = phase.controlBounds.lower;
          ub_phase(U_indizes(:,m)) = phase.controlBounds.upper;
        end
        
        % parameters
        for m=size(P_indizes,2)
          lb_phase(P_indizes(:,m)) = phase.parameterBounds.lower;
          ub_phase(P_indizes(:,m)) = phase.parameterBounds.upper;
        end
        
        % timesteps
        if isempty(phase.T)
          lb_phase(H_indizes) = Simultaneous.h_min;
        else
          lb_phase(H_indizes) = phase.H_norm * phase.T;
          ub_phase(H_indizes) = phase.H_norm * phase.T;
        end
        lowerBounds{k} = lb_phase;
        upperBounds{k} = ub_phase;
      end
      lowerBounds = vertcat(lowerBounds{:});
      upperBounds = vertcat(upperBounds{:});
      
    end
    
    function [nv_phase,N] = nvars(H_norm, nx, ni, nu, np)
      % number of control intervals
      N = length(H_norm);
      
      % N control interval which each have states, integrator vars,
      % controls, parameters, and timesteps.
      % Ends with a single state.
      nv_phase = N*nx + N*ni + N*nu + N*np + N + nx;
    end
    
    function [costs,constraints,constraints_lb,constraints_ub,times,x0,p0] = ...
        simultaneous(H_norm, T, nx, ni, nu, np, phaseVars, integrator_map, ...
                     pathcost_fun, pathcon_fun)
      

      [nv_phase,N] = Simultaneous.nvars(H_norm, nx, ni, nu, np);
      
      % number of variables in one control interval
      % + 1 for the timestep
      nci = nx+ni+nu+np+1;
      
      % Finds indizes of the variables in the NlpVars array.
      % cellfun is similar to python list comprehension 
      % e.g. [range(start_i,start_i+nx) for start_i in range(1,nv,nci)]
      X_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+nx-1)', 1:nci:nv_phase, 'UniformOutput', false));
      I_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+ni-1)', nx+1:nci:nv_phase, 'UniformOutput', false));
      U_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+nu-1)', nx+ni+1:nci:nv_phase, 'UniformOutput', false));
      P_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i+np-1)', nx+ni+nu+1:nci:nv_phase, 'UniformOutput', false));
      H_indizes = cell2mat(arrayfun(@(start_i) (start_i:start_i)', nx+ni+nu+np+1:nci:nv_phase, 'UniformOutput', false));
      
      X = reshape(phaseVars(X_indizes), nx, N+1);
      I = reshape(phaseVars(I_indizes), ni, N);
      U = reshape(phaseVars(U_indizes), nu, N);
      P = reshape(phaseVars(P_indizes), np, N);
      H = reshape(phaseVars(H_indizes), 1 , N);
          
      pcon = cell(1,N);
      pcon_lb = cell(1,N);
      pcon_ub = cell(1,N);
      pcost = 0;
      for k=1:N
        [pcon{k}, pcon_lb{k}, pcon_ub{k}] = pathcon_fun(k, N, X(:,k), P(:,k));
        pcost = pcost + pathcost_fun(k, N, X(:,k), P(:,k));
      end    
      
      pcon = horzcat(pcon{:});
      pcon_lb = horzcat(pcon_lb{:});
      pcon_ub = horzcat(pcon_ub{:});
      
      T0 = [0, cumsum(H(:,1:end-1))];
      
      [xend_arr, cost_arr, int_eq_arr, int_times] = integrator_map(X(:,1:end-1), I, U, H, P);
      
      for k=1:size(int_times,1)
        int_times(k,:) = T0 + int_times(k,:);
      end
                
      % timestep constraints
      h_eq = [];
      h_eq_lb = [];
      h_eq_ub = [];
      
      if isempty(T)      
        % h0 = h_1_hat / h_0_hat * h1 = h_2_hat / h_1_hat * h2 ...
        H_ratio = H_norm(1:end-1)./H_norm(2:end);
        h_eq = H_ratio .* H(:,2:end) - H(:,1:end-1);
        h_eq_lb = zeros(1, N-1);
        h_eq_ub = zeros(1, N-1);
      end
      
      % Parameter constraints 
      % p0=p1=p2=p3 ...
      p_eq = P(:,2:end)-P(:,1:end-1);
      p_eq_lb = zeros(np, N-1);
      p_eq_ub = zeros(np, N-1);
      
      % continuity (nx x N)
      continuity = xend_arr - X(:,2:end);
      
      % merge integrator equations, continuity, and path constraints,
      % timesteps constraints
      shooting_eq    = [int_eq_arr(:,1:N-1);   continuity(:,1:N-1);   pcon;     h_eq;     p_eq];
      shooting_eq_lb = [zeros(ni,N-1);         zeros(nx,N-1);         pcon_lb;  h_eq_lb;  p_eq_lb];
      shooting_eq_ub = [zeros(ni,N-1);         zeros(nx,N-1);         pcon_ub;  h_eq_ub;  p_eq_ub];
      
      % reshape shooting equations to column vector, append integrator and
      % continuity equations
      constraints    = [shooting_eq(:);    int_eq_arr(:,N); continuity(:,N)];
      constraints_lb = [shooting_eq_lb(:); zeros(ni,1);     zeros(nx,1)    ];
      constraints_ub = [shooting_eq_ub(:); zeros(ni,1);     zeros(nx,1)    ];

      % sum all costs
      costs = sum(cost_arr) + pcost;
      
      % times
      times = [T0; int_times; T0];
      times = [times(:); T0(end)+H(end)];
      
      x0 = X(:,1);
      p0 = P(:,1);
      
    end % getNLPFun    
  end % methods
end % classdef

