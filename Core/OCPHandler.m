
classdef OCPHandler < handle
  properties (Access = public)
    pathCostsFun
    arrivalCostsFun
    boundaryConditionsFun
    pathConstraintsFun
    discreteCostsFun
  end
  
  properties(Access = private)
    ocp    
    system
    nlpVarsStruct
    options
  end

  methods
    
    function self = OCPHandler(ocp,system,nlpVarsStruct,options)
      self.ocp = ocp;
      self.system = system;
      self.nlpVarsStruct = nlpVarsStruct;
      self.options = options;
      
      % variable sizes
      sx = system.statesStruct.size();
      sz = system.algVarsStruct.size();
      su = system.controlsStruct.size();
      sp = system.parametersStruct.size();
      st = [1,1];
      sv = nlpVarsStruct.size;

      fhPC = @(self,varargin) self.getPathCosts(varargin{:});
      self.pathCostsFun = OclFunction(self, fhPC, {sx,sz,su,st,st,sp}, 1);
      
      fhAC = @(self,varargin) self.getArrivalCosts(varargin{:});
      self.arrivalCostsFun = OclFunction(self, fhAC, {sx,st,sp}, 1);
      
      fhBC = @(self,varargin)self.getBoundaryConditions(varargin{:});
      self.boundaryConditionsFun = OclFunction(self, fhBC, {sx,sx,sp}, 3);
      
      fhPConst = @(self,varargin)self.getPathConstraints(varargin{:});
      self.pathConstraintsFun = OclFunction(self, fhPConst, {sx,st,sp}, 3);
      
      fhDC = @(self,varargin)self.getDiscreteCosts(varargin{:});
      self.discreteCostsFun = OclFunction(self, fhDC, {sv}, 1);
      
    end
    
    function r = getPathCosts(self,states,algVars,controls,time,endTime,parameters)
      self.ocp.thisPathCosts = 0;
      
      if self.options.controls_regularization
        self.ocp.thisPathCosts = self.options.controls_regularization_value*(controls.'*controls);
      end
      
      x = Variable.create(self.system.statesStruct,states);
      z = Variable.create(self.system.algVarsStruct,algVars);
      u = Variable.create(self.system.controlsStruct,controls);
      p = Variable.create(self.system.parametersStruct,parameters);
      t = Variable.Matrix(endTime);
      
      self.ocp.fh.pcH(self.ocp,x,z,u,time,t,p);
      r = self.ocp.thisPathCosts;
    end
    
    function r = getArrivalCosts(self,states,endTime,parameters)
      self.ocp.thisArrivalCosts = 0;
      x = Variable.create(self.system.statesStruct,states);
      p = Variable.create(self.system.parametersStruct,parameters);
      t = Variable.Matrix(endTime);
      
      self.ocp.fh.acH(self.ocp,x,t,p);
      r = self.ocp.thisArrivalCosts;
    end
    
    function [val,lb,ub] = getPathConstraints(self,states,time,parameters)
      self.ocp.thisPathConstraints = OclConstraint();
      x = Variable.create(self.system.statesStruct,states);
      p = Variable.create(self.system.parametersStruct,parameters);
      t = Variable.Matrix(time);
      
      self.ocp.fh.pconH(self.ocp,x,t,p);
      val = self.ocp.thisPathConstraints.values;
      lb = self.ocp.thisPathConstraints.lowerBounds;
      ub = self.ocp.thisPathConstraints.upperBounds;
    end
    
    function [val,lb,ub] = getBoundaryConditions(self,initialStates,finalStates,parameters)
      self.ocp.thisBoundaryConditions = OclConstraint();
      x0 = Variable.create(self.system.statesStruct,initialStates);
      xF = Variable.create(self.system.statesStruct,finalStates);
      p = Variable.create(self.system.parametersStruct,parameters);
      
      self.ocp.fh.bcH(self.ocp,x0,xF,p);
      val = Variable.getValue(self.ocp.thisBoundaryConditions.values);
      lb = Variable.getValue(self.ocp.thisBoundaryConditions.lowerBounds);
      ub = Variable.getValue(self.ocp.thisBoundaryConditions.upperBounds);
    end
    
    function r = getDiscreteCosts(self,varsValue)
      self.ocp.thisDiscreteCosts = 0;
      v = Variable.create(self.nlpVarsStruct,varsValue);
      self.ocp.fh.dcH(self.ocp,v);
      r = self.ocp.thisDiscreteCosts;
    end

    function callbackFunction(self,nlpVars,variableValues)
      nlpVars.set(variableValues);
      self.ocp.fh.icH(self.ocp,nlpVars);
    end

  end
  
end

